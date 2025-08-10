#!/bin/bash

# Source builds for ComfyUI - xformers, SageAttention, and infinite-image-browsing
# This script builds libraries from source for optimal performance
set -e

build_source_builds_main() {
	echo "🔨 Building libraries from source..."
	
	#check current torch version and xformers version
	$COMFYUI_VENV_PIP show torch

	#check if sageattention is installed
	echo "🔍 Checking SageAttention installation..."
	# if ! $COMFYUI_VENV_PIP show sageattention >/dev/null 2>&1; then
	# 	echo "❌ SageAttention is not installed."
	# 	exit 1
	# else
		# echo "✅ SageAttention is installed."
	# fi

	build_source_xformers
	cleanup_build_artifacts
	
	echo "✅ Source builds completed!"
}

cleanup_build_artifacts() {
	echo "🧹 Cleaning up build artifacts..."
	
	# Remove build dependencies
	source "$COMFYUI_VENV/bin/activate"
	uv pip uninstall ninja cmake wheel build setuptools-scm || true
	
	# Clean pip cache
	uv cache clean || true
	pip cache purge || true
	
	# Clean apt cache
	apt-get clean
	rm -rf /var/lib/apt/lists/*
	
	# Remove temp files
	rm -rf /tmp/* /var/tmp/*
	
	echo "✅ Cleanup completed"
}
build_source_xformers() {
	# Usage: build_source_xformers "8.9;9.0;9.0a"
	local REQ_ARCHS="${1:-8.9;9.0;9.0a}"
	local ARCHS_SEMI="${REQ_ARCHS//,/;}"   # "8.9;9.0;9.0a"
	local ARCHS_NUM="89;90"                # keep CMake numeric; handle 90a via CUTLASS

	echo "🚀 Building xFormers for SMs [${ARCHS_SEMI}] with FlashAttention…"
	source "$COMFYUI_VENV/bin/activate" || { echo "Venv missing: $COMFYUI_VENV"; return 1; }

	# Match CUDA to torch.version.cuda (e.g., 12.8)
	local TORCH_CUDA_VER
	TORCH_CUDA_VER="$(python - <<-'PY'
	import torch; print((torch.version.cuda or "").strip())
	PY
	)"

	[[ -n "$TORCH_CUDA_VER" && -d "/usr/local/cuda-${TORCH_CUDA_VER}" ]] \
		&& export CUDA_HOME="/usr/local/cuda-${TORCH_CUDA_VER}" \
		|| export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
	export PATH="${CUDA_HOME}/bin:${PATH}"
	export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${CUDA_HOME}/lib64/stubs:${LD_LIBRARY_PATH:-}"

	command -v nvcc >/dev/null || { echo "❌ nvcc not found (CUDA_HOME=$CUDA_HOME)"; return 1; }

	# Toolchain
	uv pip install -U setuptools wheel ninja cmake >/dev/null 2>&1 || true
	if command -v gcc-12 >/dev/null 2>&1 && command -v g++-12 >/dev/null 2>&1; then
		echo "✅ Using GCC 12"
		export CC="$(command -v gcc-12)"; export CXX="$(command -v g++-12)"; export CUDAHOSTCXX="$CXX"
	elif command -v gcc-11 >/dev/null 2>&1 && command -v g++-11 >/dev/null 2>&1; then
		echo "✅ Using GCC 11"	
		export CC="$(command -v gcc-11)"; export CXX="$(command -v g++-11)"; export CUDAHOSTCXX="$CXX"
	elif command -v gcc-10 >/dev/null 2>&1 && command -v g++-10 >/dev/null 2>&1; then
		echo "✅ Using GCC 10"
		export CC="$(command -v gcc-10)"; export CXX="$(command -v g++-10)"; export CUDAHOSTCXX="$CXX"
	else
		echo "❌ No suitable GCC found (need gcc-12/11/10)"; return 1
	fi

  # CUDA/PyTorch hints
  export FORCE_CUDA=1
  # Keep 90a out of TORCH/CMAKE lists to avoid CMake parsing issues; drive it via CUTLASS
  export TORCH_CUDA_ARCH_LIST="${ARCHS_SEMI//;9.0a/}"   # "8.9;9.0"
  export CMAKE_ARGS="-DCMAKE_CUDA_ARCHITECTURES=${ARCHS_NUM}"  # "89;90"
  export CUDAARCHS="${ARCHS_NUM}"
  [[ "$ARCHS_SEMI" == *"9.0a"* ]] && export CUTLASS_NVCC_ARCHS="90a" || unset CUTLASS_NVCC_ARCHS
  export XFORMERS_BUILD_FLASH_ATTENTION=ON
  export NVCC_FLAGS="-Xptxas -O2"
  export TORCH_CUDA_FLAGS="$NVCC_FLAGS"
  export LDFLAGS="-L${CUDA_HOME}/lib64/stubs ${LDFLAGS:-}"
  export CXXFLAGS="${CXXFLAGS:-} -Wno-error"

  echo "CUDA_HOME=$CUDA_HOME"
  echo "TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST"
  echo "CMAKE_ARGS=$CMAKE_ARGS"

  # Fresh clone WITH submodules
  cd /tmp && rm -rf xformers
  git clone --depth=1 --recurse-submodules --shallow-submodules https://github.com/facebookresearch/xformers.git
  cd xformers || return 1
  # Belt & suspenders: ensure submodules are present even if the shallow flags fail
  git submodule update --init --recursive --depth 1 || git submodule update --init --recursive

  echo "🔨 Building xFormers…"
  if uv pip install -v --no-build-isolation . 2>&1 | tee build.log; then
    $COMFYUI_VENV_PIP show xformers >/dev/null 2>&1 || {
      echo "❌ Built but not importable."; grep -nEi "error:|fatal error:|undefined reference|collect2:" build.log | tail -n80 || tail -n80 build.log; return 1; }
    echo "✅ xFormers build completed."
  else
    echo "❌ Build failed."
    grep -nEi "error:|fatal error:|undefined reference|collect2:" build.log | tail -n80 || tail -n80 build.log
    return 1
  fi

  cd / && rm -rf /tmp/xformers
  echo "✅ Done for SMs [${ARCHS_SEMI}]"
}

build_source_builds_main "$@"
