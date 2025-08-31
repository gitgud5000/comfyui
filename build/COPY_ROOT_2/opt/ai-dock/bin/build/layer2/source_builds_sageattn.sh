#!/bin/bash

# Source builds for ComfyUI - SageAttention
# This script builds libraries from source for optimal performance
set -euo pipefail

build_source_builds_main() {
    echo "🔨 Building libraries from source..."
    source "$COMFYUI_VENV/bin/activate"

    uv pip install --upgrade pip

    # echo "🔄 Rebuilding libraries Torch"
    echo "🔄 Rebuilding libraries SageAttention"
    build_source_sageattention
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

build_source_sageattention() {
	# Usage examples:
	#   build_source_sageattention "9.0+PTX"
	#   build_source_sageattention "8.9;9.0+PTX"
	#   build_source_sageattention "8.9,9.0+PTX"
	local REQ_ARCHS="${1:-9.0}"

	# Normalize separators to semicolons; keep +PTX for PyTorch env
	local ARCHS_SEMI="${REQ_ARCHS//,/;}"   # e.g. "8.9;9.0+PTX"

	# Build numeric arch list for CMake/CUDAARCHS (no +PTX, no dots)
	local ARCHS_CMAKE
	ARCHS_CMAKE="$(echo "$ARCHS_SEMI" \
		| tr ';' '\n' \
		| sed -E 's/[[:space:]]+//g; s/\+PTX//Ig' \
		| tr -d '.' \
		| grep -E '^[0-9]+$' \
		| paste -sd';' -)"

	if [[ -z "$ARCHS_CMAKE" ]]; then
		echo "❌ Failed to derive numeric CMake architectures from '$REQ_ARCHS'."
		return 1
	fi

	echo "🧠 Building SageAttention for TORCH_CUDA_ARCH_LIST=[$ARCHS_SEMI]"
	echo "🧱 CMAKE_CUDA_ARCHITECTURES=[$ARCHS_CMAKE]"

	# ---- Python venv ----
	source "$COMFYUI_VENV/bin/activate" || { echo "Venv missing: $COMFYUI_VENV"; return 1; }

	# ---- Match CUDA to torch.version.cuda if available ----
	local TORCH_CUDA_VER
	TORCH_CUDA_VER="$(python - <<-'PY'
	import torch
	print((torch.version.cuda or "").strip())
	PY
	)"
	echo "🔥 Torch CUDA version: $TORCH_CUDA_VER"
	if [[ -n "$TORCH_CUDA_VER" && -d "/usr/local/cuda-${TORCH_CUDA_VER}" ]]; then
		export CUDA_HOME="/usr/local/cuda-${TORCH_CUDA_VER}"
	else
		export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
	fi
	export PATH="${CUDA_HOME}/bin:${PATH}"
	export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${CUDA_HOME}/lib64/stubs:${LD_LIBRARY_PATH:-}"

	# ---- Toolchain & compilers (prefer gcc-12, fallback to 11/10) ----
	uv pip install -U setuptools wheel ninja cmake >/dev/null 2>&1 || true
	if command -v gcc-12 >/dev/null 2>&1 && command -v g++-12 >/dev/null 2>&1; then
		echo "✅ Using GCC 12"
		export CC="$(command -v gcc-12)"; export CXX="$(command -v g++-12)"; export CUDAHOSTCXX="$CXX"
	elif command -v gcc-11 >/dev/null 2>&1 && command -v g++-11 >/devnull 2>&1; then
		echo "✅ Using GCC 11"
		export CC="$(command -v gcc-11)"; export CXX="$(command -v g++-11)"; export CUDAHOSTCXX="$CXX"
	elif command -v gcc-10 >/dev/null 2>&1 && command -v g++-10 >/dev/null 2>&1; then
		echo "✅ Using GCC 10"
		export CC="$(command -v gcc-10)"; export CXX="$(command -v g++-10)"; export CUDAHOSTCXX="$CXX"
	else
		echo "❌ No suitable GCC found! Please install gcc-12/11/10."
		return 1
	fi

	# ---- CUDA/PyTorch build hints ----
	export FORCE_CUDA=1
	export TORCH_CUDA_ARCH_LIST="$ARCHS_SEMI"                    # e.g. "8.9;9.0+PTX"
	export CMAKE_ARGS="-DCMAKE_CUDA_ARCHITECTURES=${ARCHS_CMAKE}" # e.g. "89;90"
	export CUDAARCHS="${ARCHS_CMAKE}"                            # belt & suspenders
	export NVCC_FLAGS="-Xptxas -O2"
	export TORCH_CUDA_FLAGS="$NVCC_FLAGS"
	export LDFLAGS="-L${CUDA_HOME}/lib64/stubs ${LDFLAGS:-}"
	export CXXFLAGS="${CXXFLAGS:-} -Wno-error"
	export MAX_JOBS="$(nproc)"
	export CMAKE_BUILD_PARALLEL_LEVEL="$(nproc)"
	export NVCC_THREADS=30

	# ---- Sanity check ----
	nvcc --version || { echo "nvcc not found (CUDA_HOME=$CUDA_HOME)"; return 1; }
	echo "CUDA_HOME=$CUDA_HOME"
	echo "TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST"
	echo "CMAKE_ARGS=$CMAKE_ARGS"

	# ---- Fresh clone + patch ----
	cd /tmp && rm -rf SageAttention
	git clone --depth=1 https://github.com/woct0rdho/SageAttention
	# git clone --depth=1 https://github.com/thu-ml/SageAttention
	cd SageAttention || return 1
	# echo "🔧 Applying PR #147 patch…"
	# curl -sL https://github.com/thu-ml/SageAttention/pull/147.patch | patch -p1

	# ---- Build ----
	echo "🔨 Building SageAttention…"
	if uv pip install -v --no-build-isolation . 2>&1 | tee build.log; then
		$COMFYUI_VENV_PIP show sageattention >/dev/null 2>&1 || {
			echo "❌ Built but not importable."
			grep -nEi "error:|fatal error:|undefined reference|collect2:" build.log | tail -n80 || tail -n80 build.log
			return 1
		}
		echo "✅ SageAttention build completed."
	else
		echo "❌ Build failed."
		grep -nEi "error:|fatal error:|undefined reference|collect2:" build.log | tail -n80 || tail -n80 build.log
		return 1
	fi

    # echo 🖥️🖥️🖥️ Checking compiled architectures
    # for so in /opt/environments/python/comfyui/lib/python3.12/site-packages/sageattention/_*.so; do
    #     echo ">> $so"
    #     readelf -p .nv_fatbin "$so" 2>/dev/null | grep -Eo 'sm_[0-9]+' | sort -u || \
    #     strings "$so" | grep -Eo 'sm_[0-9]+' | sort -u
    #     readelf -p .nv_fatbin "$so" 2>/dev/null | grep -Eo 'compute_[0-9]+' | sort -u || \
    #     strings "$so" | grep -Eo 'compute_[0-9]+' | sort -u
    # done

	# ---- Cleanup ----
	cd / && rm -rf /tmp/SageAttention
	echo "✅ Done for SMs [${ARCHS_SEMI}]"
}
# build_source_sageattention() {
# 	# Usage examples:
# 	#   build_source_sageattention "9.0+PTX"
# 	#   build_source_sageattention "8.9;9.0+PTX"
# 	#   build_source_sageattention "8.9,9.0+PTX"
# 	local REQ_ARCHS="${1:-9.0}"

# 	# Normalize separators to semicolons; keep +PTX for PyTorch env
# 	local ARCHS_SEMI="${REQ_ARCHS//,/;}"   # e.g. "8.9;9.0+PTX"

# 	# Build numeric arch list for CMake/CUDAARCHS (no +PTX, no dots)
# 	local ARCHS_CMAKE
# 	ARCHS_CMAKE="$(echo "$ARCHS_SEMI" \
# 		| tr ';' '\n' \
# 		| sed -E 's/[[:space:]]+//g; s/\+PTX//Ig' \
# 		| tr -d '.' \
# 		| grep -E '^[0-9]+$' \
# 		| paste -sd';' -)"

# 	if [[ -z "$ARCHS_CMAKE" ]]; then
# 		echo "❌ Failed to derive numeric CMake architectures from '$REQ_ARCHS'."
# 		return 1
# 	fi

# 	echo "🧠 Building SageAttention for TORCH_CUDA_ARCH_LIST=[$ARCHS_SEMI]"
# 	echo "🧱 CMAKE_CUDA_ARCHITECTURES=[$ARCHS_CMAKE]"

# 	# ---- Python venv ----
# 	source "$COMFYUI_VENV/bin/activate" || { echo "Venv missing: $COMFYUI_VENV"; return 1; }

# 	# ---- Match CUDA to torch.version.cuda if available ----
# 	local TORCH_CUDA_VER
# 	TORCH_CUDA_VER="$(python - <<-'PY'
# 	import torch
# 	print((torch.version.cuda or "").strip())
# 	PY
# 	)"
# 	echo "🔥 Torch CUDA version: $TORCH_CUDA_VER"
# 	if [[ -n "$TORCH_CUDA_VER" && -d "/usr/local/cuda-${TORCH_CUDA_VER}" ]]; then
# 		export CUDA_HOME="/usr/local/cuda-${TORCH_CUDA_VER}"
# 	else
# 		export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
# 	fi
# 	export PATH="${CUDA_HOME}/bin:${PATH}"
# 	export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${CUDA_HOME}/lib64/stubs:${LD_LIBRARY_PATH:-}"

# 	# ---- Toolchain & compilers (prefer gcc-12, fallback to 11/10) ----
# 	uv pip install -U setuptools wheel ninja cmake >/dev/null 2>&1 || true
# 	if command -v gcc-12 >/dev/null 2>&1 && command -v g++-12 >/dev/null 2>&1; then
# 		echo "✅ Using GCC 12"
# 		export CC="$(command -v gcc-12)"; export CXX="$(command -v g++-12)"; export CUDAHOSTCXX="$CXX"
# 	elif command -v gcc-11 >/dev/null 2>&1 && command -v g++-11 >/devnull 2>&1; then
# 		echo "✅ Using GCC 11"
# 		export CC="$(command -v gcc-11)"; export CXX="$(command -v g++-11)"; export CUDAHOSTCXX="$CXX"
# 	elif command -v gcc-10 >/dev/null 2>&1 && command -v g++-10 >/dev/null 2>&1; then
# 		echo "✅ Using GCC 10"
# 		export CC="$(command -v gcc-10)"; export CXX="$(command -v g++-10)"; export CUDAHOSTCXX="$CXX"
# 	else
# 		echo "❌ No suitable GCC found! Please install gcc-12/11/10."
# 		return 1
# 	fi

# 	# ---- CUDA/PyTorch build hints ----
# 	export FORCE_CUDA=1
# 	export TORCH_CUDA_ARCH_LIST="$ARCHS_SEMI"                    # e.g. "8.9;9.0+PTX"
# 	export CMAKE_ARGS="-DCMAKE_CUDA_ARCHITECTURES=${ARCHS_CMAKE}" # e.g. "89;90"
# 	export CUDAARCHS="${ARCHS_CMAKE}"                            # belt & suspenders
# 	export NVCC_FLAGS="-Xptxas -O2"
# 	export TORCH_CUDA_FLAGS="$NVCC_FLAGS"
# 	export LDFLAGS="-L${CUDA_HOME}/lib64/stubs ${LDFLAGS:-}"
# 	export CXXFLAGS="${CXXFLAGS:-} -Wno-error"
# 	export MAX_JOBS="$(nproc)"
# 	export CMAKE_BUILD_PARALLEL_LEVEL="$(nproc)"

# 	# ---- Sanity check ----
# 	nvcc --version || { echo "nvcc not found (CUDA_HOME=$CUDA_HOME)"; return 1; }
# 	echo "CUDA_HOME=$CUDA_HOME"
# 	echo "TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST"
# 	echo "CMAKE_ARGS=$CMAKE_ARGS"

# 	# ---- Fresh clone + patch ----
# 	cd /tmp && rm -rf SageAttention
# 	git clone --depth=1 https://github.com/thu-ml/SageAttention
# 	cd SageAttention || return 1
# 	echo "🔧 Applying PR #147 patch…"
# 	curl -sL https://github.com/thu-ml/SageAttention/pull/147.patch | patch -p1

# 	# ---- Build ----
# 	echo "🔨 Building SageAttention…"
# 	if uv pip install -v --no-build-isolation . 2>&1 | tee build.log; then
# 		$COMFYUI_VENV_PIP show sageattention >/dev/null 2>&1 || {
# 			echo "❌ Built but not importable."
# 			grep -nEi "error:|fatal error:|undefined reference|collect2:" build.log | tail -n80 || tail -n80 build.log
# 			return 1
# 		}
# 		echo "✅ SageAttention build completed."
# 	else
# 		echo "❌ Build failed."
# 		grep -nEi "error:|fatal error:|undefined reference|collect2:" build.log | tail -n80 || tail -n80 build.log
# 		return 1
# 	fi

#     # echo 🖥️🖥️🖥️ Checking compiled architectures
#     # for so in /opt/environments/python/comfyui/lib/python3.12/site-packages/sageattention/_*.so; do
#     #     echo ">> $so"
#     #     readelf -p .nv_fatbin "$so" 2>/dev/null | grep -Eo 'sm_[0-9]+' | sort -u || \
#     #     strings "$so" | grep -Eo 'sm_[0-9]+' | sort -u
#     #     readelf -p .nv_fatbin "$so" 2>/dev/null | grep -Eo 'compute_[0-9]+' | sort -u || \
#     #     strings "$so" | grep -Eo 'compute_[0-9]+' | sort -u
#     # done

# 	# ---- Cleanup ----
# 	cd / && rm -rf /tmp/SageAttention
# 	echo "✅ Done for SMs [${ARCHS_SEMI}]"
# }

# build_source_sageattention() {
#     # Usage: build_source_sageattention "8.9;9.0"  (commas or semicolons both ok)
#     local REQ_ARCHS="${1:-8.9;9.0}"
#     local ARCHS_SEMI="${REQ_ARCHS//,/;}"   # "8.9;9.0"
#     local ARCHS_NUM="${ARCHS_SEMI//./}"    # "89;90"
#     echo "🧠 Building SageAttention for SMs [${ARCHS_SEMI}]…"

#     # ---- Python venv ----
#     source "$COMFYUI_VENV/bin/activate" || { echo "Venv missing: $COMFYUI_VENV"; return 1; }

#     # ---- Match CUDA to torch.version.cuda if available ----
#     local TORCH_CUDA_VER
#     TORCH_CUDA_VER="$(python - <<'PY'
# import torch, sys
# print((torch.version.cuda or "").strip())
# PY
# )"
#     echo "🔥Torch CUDA version: $TORCH_CUDA_VER"
#     if [[ -n "$TORCH_CUDA_VER" && -d "/usr/local/cuda-${TORCH_CUDA_VER}" ]]; then
#         export CUDA_HOME="/usr/local/cuda-${TORCH_CUDA_VER}"
#     else
#         export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
#     fi
#     export PATH="${CUDA_HOME}/bin:${PATH}"
#     export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${CUDA_HOME}/lib64/stubs:${LD_LIBRARY_PATH:-}"

#     # ---- Toolchain & compilers (prefer gcc-12, fallback to 11) ----
#     uv pip install -U setuptools wheel ninja cmake >/dev/null 2>&1 || true
#     if command -v gcc-12 >/dev/null 2>&1 && command -v g++-12 >/dev/null 2>&1; then
#         echo "✅ Using GCC 12"
#         export CC="$(command -v gcc-12)"
#         export CXX="$(command -v g++-12)"
#         export CUDAHOSTCXX="$CXX"
#     elif command -v gcc-11 >/dev/null 2>&1 && command -v g++-11 >/dev/null 2>&1; then
#         echo "✅ Using GCC 11"
#         export CC="$(command -v gcc-11)"
#         export CXX="$(command -v g++-11)"
#         export CUDAHOSTCXX="$CXX"
#     elif command -v gcc-10 >/dev/null 2>&1 && command -v g++-10 >/dev/null 2>&1; then
#         echo "✅ Using GCC 10"
#         export CC="$(command -v gcc-10)"
#         export CXX="$(command -v g++-10)"
#         export CUDAHOSTCXX="$CXX"
#     else
#         echo "❌ No suitable GCC found! Please install gcc-12, gcc-11, or gcc-10."
#         return 1
#     fi

#     # ---- CUDA/PyTorch build hints ----
#     export FORCE_CUDA=1
#     export TORCH_CUDA_ARCH_LIST="${ARCHS_SEMI}"                 # e.g. "8.9;9.0"
#     export CMAKE_ARGS="-DCMAKE_CUDA_ARCHITECTURES=${ARCHS_NUM}" # e.g. "89;90"
#     export CUDAARCHS="${ARCHS_NUM}"                             # belt & suspenders
#     export NVCC_FLAGS="-Xptxas -O2"
#     export TORCH_CUDA_FLAGS="$NVCC_FLAGS"
#     export LDFLAGS="-L${CUDA_HOME}/lib64/stubs ${LDFLAGS:-}"
#     export CXXFLAGS="${CXXFLAGS:-} -Wno-error"
#     export MAX_JOBS="$(nproc)"
#     export CMAKE_BUILD_PARALLEL_LEVEL="$(nproc)"

#     # ---- Sanity check ----
#     nvcc --version || { echo "nvcc not found (CUDA_HOME=$CUDA_HOME)"; return 1; }
#     echo "CUDA_HOME=$CUDA_HOME"
#     echo "TORCH_CUDA_ARCH_LIST=$TORCH_CUDA_ARCH_LIST"
#     echo "CMAKE_ARGS=$CMAKE_ARGS"

#     # ---- Fresh clone + patch ----
#     cd /tmp && rm -rf SageAttention
#     git clone --depth=1 https://github.com/thu-ml/SageAttention
#     cd SageAttention || return 1
#     echo "🔧 Applying PR #147 patch…"
#     curl -sL https://github.com/thu-ml/SageAttention/pull/147.patch | patch -p1

#     # ---- Build ----
#     echo "🔨 Building SageAttention…"
#     if uv pip install -v --no-build-isolation . 2>&1 | tee build.log; then
#         $COMFYUI_VENV_PIP show sageattention >/dev/null 2>&1 || {
#             echo "❌ Built but not importable."
#             grep -nEi "error:|fatal error:|undefined reference|collect2:" build.log | tail -n80 || tail -n80 build.log
#             return 1
#         }
#         echo "✅ SageAttention build completed."
#     else
#         echo "❌ Build failed."
#         grep -nEi "error:|fatal error:|undefined reference|collect2:" build.log | tail -n80 || tail -n80 build.log
#         return 1
#     fi

#     # ---- Cleanup ----
#     cd / && rm -rf /tmp/SageAttention
#     echo "✅ Done for SMs [${ARCHS_SEMI}]"
# }

# build_source_sageattentionx() {
#     # 1) SM list (e.g. "8.9;12.0"), default → 8.9;12.0
#     # local GPU_ARCH_LIST="${1:-8.9;9.0}" this uses commas not semicolons bc of patch
#     local GPU_ARCH_LIST="${1:-8.9,9.0}" # this uses commas not semicolons bc of patch, not an error
#     echo "🧠 Building SageAttention for SMs [${GPU_ARCH_LIST}]..."

#     # 2) Activate venv and force CUDA-path even on GPU-less host
#     source "$COMFYUI_VENV/bin/activate"
#     export TORCH_CUDA_ARCH_LIST="${GPU_ARCH_LIST}"
#     export FORCE_CUDA=1

#     # 3) Clone fresh
#     cd /tmp && rm -rf SageAttention  # Use /tmp instead of /opt
#     git clone --depth=1 https://github.com/thu-ml/SageAttention
#     cd SageAttention

#     echo "🔧 Applying PR #147 patch to setup.py…"
#     curl -sL https://github.com/thu-ml/SageAttention/pull/147.patch \
#         | patch -p1

#     # Ensure build toolchain and CUDA env (works on GPU-less hosts)
#     export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
#     export PATH="${CUDA_HOME}/bin:${PATH}"
#     export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${CUDA_HOME}/lib64/stubs:${LD_LIBRARY_PATH:-}"
#     export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$CUDA_HOME/lib64/stubs:${LD_LIBRARY_PATH:-}"
#     export LDFLAGS="-L$CUDA_HOME/lib64/stubs"
#     CMAKE_CUDA_ARCHITECTURES="89;90"
#     export CMAKE_BUILD_PARALLEL_LEVEL="$(nproc)"   
#     export NVCC_FLAGS="-Xptxas -O2"
# 	export TORCH_CUDA_FLAGS="$NVCC_FLAGS"
# 	# export NVCC_THREADS=14

#     export CC=/usr/bin/gcc-12
#     export CXX=/usr/bin/g++-12
#     export CUDAHOSTCXX=/usr/bin/g++-12
#     #check if gcc 12 is available
#     if ! command -v /usr/bin/gcc-12 &> /dev/null; then
#         echo "❌ gcc-12 not found!"
#         exit 1
#     else
#         echo "✅ gcc-12 found!"
#     fi

#     uv pip install -U setuptools wheel ninja cmake >/dev/null 2>&1 || true
#     echo "🔥LD LIB PATH: $LD_LIBRARY_PATH"
#     # Auto-detect and force parallel build
#     echo "🔨 Starting SageAttention build..."
#     nvcc --version || { echo "nvcc not found in PATH"; exit 1; }
#     export MAX_JOBS="$(nproc)"
#     echo "MAX JOBS: $MAX_JOBS"

#     # if python setup.py build_ext --library-dirs=/usr/local/cuda/lib64/stubs 2>&1 | tee build.log; then
#     if uv pip install -v --no-build-isolation .  2>&1 | tee build.log; then
#         # check if sage attention available in environment in pip
#         $COMFYUI_VENV_PIP show sageattention >/dev/null 2>&1 || {
#             echo "❌ SageAttention build failed! Package not found in environment."
#             echo "📋 Last 20 lines of build output:"
#             tail -n20 build.log || echo "No build log available"
#             echo "💡 Common fixes:"
#             echo "  - Check CUDA toolkit is installed"
#             echo "  - Verify TORCH_CUDA_ARCH_LIST=${GPU_ARCH_LIST}"
#             echo "  - Ensure sufficient disk space"
#             exit 1
#         }

        
#         echo "✅ SageAttention build completed successfully"
#     else
#         echo "❌ SageAttention build failed!"
#         echo "📋 Last 20 lines of build output:"
#         tail -n20 build.log || echo "No build log available"
#         echo "💡 Common fixes:"
#         echo "  - Check CUDA toolkit is installed"
#         echo "  - Verify TORCH_CUDA_ARCH_LIST=${GPU_ARCH_LIST}"
#         echo "  - Ensure sufficient disk space"
#         exit 1
#     fi

#     # 6) Cleanup
#     cd / && rm -rf /tmp/SageAttention

#     echo "✅ SageAttention built for SMs [${GPU_ARCH_LIST}]"
# }

build_source_builds_main "$@"
