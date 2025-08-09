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
	if ! $COMFYUI_VENV_PIP show sageattention >/dev/null 2>&1; then
		echo "❌ SageAttention is not installed."
		exit 1
	else
		echo "✅ SageAttention is installed."
	fi

	build_source_xformers
	cleanup_build_artifacts
	
	echo "✅ Source builds completed!"
}

cleanup_build_artifacts() {
	echo "🧹 Cleaning up build artifacts..."
	
	# Remove build dependencies
	source "$COMFYUI_VENV/bin/activate"
	uv pip uninstall ninja cmake wheel build setuptools-scm -y || true
	
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
  echo "🚀 Building xFormers from source (sm_89, sm_90, sm_90a) with FlashAttention..."

    # 0. Pre-check: nvcc & CUDA toolkit
    if ! command -v nvcc &>/dev/null; then
        echo "❌ nvcc not found! Please install CUDA 12.8 toolkit." >&2
        return 1
    fi
  	source "$COMFYUI_VENV/bin/activate"

	export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
	export PATH="$CUDA_HOME/bin:$PATH"
	export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$CUDA_HOME/lib64/stubs:${LD_LIBRARY_PATH:-}"

	uv pip install -U pip setuptools wheel ninja

	# <<< new bits >>>
	export TORCH_CUDA_ARCH_LIST="8.9;9.0;9.0a"
	export CMAKE_CUDA_ARCHITECTURES="89;90;90a"
	export CUTLASS_NVCC_ARCHS="90a"
	export FORCE_CUDA=1
	export XFORMERS_BUILD_FLASH_ATTENTION=ON
	# export MAX_JOBS=14
	# export NVCC_THREADS=14
	export NVCC_FLAGS="-Xptxas -O2"
	export TORCH_CUDA_FLAGS="$NVCC_FLAGS"
	# optionally: export NVCC_FLAGS="-Xptxas -O2 --disable-optimizer"

	uv pip install -v --no-build-isolation \
		-U git+https://github.com/facebookresearch/xformers.git@main#egg=xformers
	# or pin a known-good commit if main explodes

	echo "🔍 Verifying..."
	python - <<-'PY'
		import torch, xformers
		print("CUDA:", torch.version.cuda)
		import subprocess, sys
		subprocess.run([sys.executable, "-m", "xformers.info"], check=False)
		PY
}

build_source_xformers22() {
    echo "🚀 Building xFormers from source (sm_89, sm_90) with FlashAttention..."

    # 0. Pre-check: nvcc & CUDA toolkit
    if ! command -v nvcc &>/dev/null; then
        echo "❌ nvcc not found! Please install CUDA 12.8 toolkit." >&2
        return 1
    fi
    echo "✅ nvcc found"
    CUDA_TOOLKIT_VER=$(nvcc --version | grep -oP "release \K[0-9]+\.[0-9]+")
    if [[ "$CUDA_TOOLKIT_VER" != "12.8" ]]; then
        echo "❌ CUDA toolkit $CUDA_TOOLKIT_VER detected; please use 12.8." >&2
        return 1
    fi
    echo "✅ CUDA toolkit $CUDA_TOOLKIT_VER detected."

    # 1. Activate virtualenv
    source "$COMFYUI_VENV/bin/activate"

    # 2. Fix CUDA paths for PyTorch build detection
	export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
    # ln -sf "$CUDA_HOME" /usr/local/cuda
    export PATH="${CUDA_HOME}/bin:${PATH}"
    export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${CUDA_HOME}/lib64/stubs:${LD_LIBRARY_PATH:-}"

    # 3. Ensure build helpers
    echo "🔧 Installing build helpers..."
    uv pip install --upgrade pip setuptools wheel ninja

    # 4. Set target architectures & force CUDA build
	# export TORCH_CUDA_ARCH_LIST="8.9;9.0"
	export TORCH_CUDA_ARCH_LIST="8.9;9.0a"
    export FORCE_CUDA=1
    export XFORMERS_BUILD_FLASH_ATTENTION=ON

    # 5. Build & install xFormers with pip (uses setup.py under the hood)
	echo "🔨 Building xFormers..."
    uv pip install -v --no-build-isolation \
        -U git+https://github.com/facebookresearch/xformers.git@main#egg=xformers

    # 6. Post-install sanity checks
    echo "🔍 Verifying PyTorch CUDA support..."
    PT_CUDA="$(python -c 'import torch; print(torch.version.cuda or \"none\")')"
    if [[ "$PT_CUDA" != 12.8* ]]; then
        echo "⚠️  PyTorch CUDA mismatch: found $PT_CUDA (expected 12.8)" >&2
    else
        echo "✅ PyTorch CUDA $PT_CUDA"
    fi

    echo "🔍 Checking xFormers kernels..."
    python -m xformers.info || true
    if python -m xformers.info | grep -q "memory_efficient_attention.*available"; then
        echo "✅ xFormers memory_efficient_attention available"
    else
        echo "❌ xFormers memory_efficient_attention NOT available!" >&2
        return 1
    fi

    # 7. Cleanup (optional)
    pip uninstall ninja -y || true
    deactivate

    echo "🎉 xFormers built & verified for CUDA sm_89 & sm_90 with FlashAttention!"
}
# build_source_xformers3() {
#     echo "🚀 Building xFormers from source (sm_89, sm_90)..."

#     # 0. Pre-check: nvcc & CUDA toolkit
#     if ! command -v nvcc &>/dev/null; then
#         echo "❌ nvcc not found! Please install CUDA 12.8 toolkit." >&2
#         return 1
#     fi
#     echo "✅ nvcc found"
#     CUDA_TOOLKIT_VER=$(nvcc --version | grep -oP "release \K[0-9]+\.[0-9]+")
#     if [[ $(echo -e "$CUDA_TOOLKIT_VER\n12.8" | sort -V | head -n1) != "12.8" ]]; then
#         echo "❌ CUDA toolkit $CUDA_TOOLKIT_VER detected; please use 12.8." >&2
#         return 1
#     fi
#     echo "✅ CUDA toolkit $CUDA_TOOLKIT_VER detected."

#     # 1. Activate virtualenv
#     source "$COMFYUI_VENV/bin/activate"
#     # 2. Ensure build helpers
# 	echo "🔧 Installing build helpers..."
#     uv pip install --upgrade pip setuptools wheel ninja compiler 
#     # 3. Set target architectures
#     export TORCH_CUDA_ARCH_LIST="8.9;9.0"
# 	export FORCE_CUDA=1
# 	# Point to CUDA toolkit and compilers; use stubs to satisfy link on GPU-less hosts
# 	export CUDA_HOME=${CUDA_HOME:-/usr/local/cuda}
# 	export CUDACXX=${CUDACXX:-$CUDA_HOME/bin/nvcc}
# 	export LD_LIBRARY_PATH="$CUDA_HOME/lib64/stubs:${LD_LIBRARY_PATH:-}"
# 	export LIBRARY_PATH="$CUDA_HOME/lib64/stubs:${LIBRARY_PATH:-}"

#     # 4. Build & install xFormers via pip (no CMake!)
#     uv pip install -v --no-build-isolation \
#       -U git+https://github.com/facebookresearch/xformers.git@main#egg=xformers
#     # (this uses setup.py under the hood) :contentReference[oaicite:0]{index=0}

#     # 5. Post-install sanity checks
#     echo "🔍 Verifying PyTorch CUDA support..."
#     PT_CUDA="$(python -c 'import torch; print(torch.version.cuda or \"none\")')"
#     if [[ "$PT_CUDA" != 12.8* ]]; then
#         echo "⚠️  PyTorch CUDA mismatch: found $PT_CUDA (expected 12.8)" >&2
#     else
#         echo "✅ PyTorch CUDA $PT_CUDA"
#     fi

#     echo "🔍 Checking xFormers kernels..."
#     if python -m xformers.info | grep -q "memory_efficient_attention.*available"; then
#         echo "✅ xFormers memory_efficient_attention available"
#     else
#         echo "❌ xFormers memory_efficient_attention NOT available!" >&2
#         return 1
#     fi
#     # usage per README: python -m xformers.info :contentReference[oaicite:1]{index=1}

#     # 6. Cleanup (optional)
#     pip uninstall ninja -y || true
#     deactivate

#     echo "🎉 xFormers built & verified for CUDA sm_89 & sm_90!"
# }
# build_source_xformerss() {
# 	echo "🚀 Building xformers from source..."
	
# 	# Activate the virtual environment
# 	source "$COMFYUI_VENV/bin/activate"

# 	# Remove any pre-existing xformers to avoid version/ABI mismatches after torch upgrades
# 	# first check if version miss matches and print "V missmatch"
# 	installed_version=$(uv pip show xformers | grep Version | cut -d " " -f 2)
# 	if [ "$installed_version" != "$XFORMERS_VERSION" ]; then
# 		echo "❌ Version mismatch detected: $installed_version (installed) vs $XFORMERS_VERSION (required)"
# 		echo "Please uninstall the existing xformers package and try again."
# 		return 1
# 	fi

# 	uv pip uninstall -y xformers || true
	
# 	cd /tmp  # Use /tmp instead of /opt
# 	git clone --recursive https://github.com/facebookresearch/xformers.git
# 	cd xformers
	
# 	# ------------------------------------------------------------
# 	# Ensure we are building WITH CUDA even on a GPU-less builder
# 	# ------------------------------------------------------------
# 	export FORCE_CUDA=1
# 	# Point to CUDA toolkit and compilers; use stubs to satisfy link on GPU-less hosts
# 	export CUDA_HOME=${CUDA_HOME:-/usr/local/cuda}
# 	export CUDACXX=${CUDACXX:-$CUDA_HOME/bin/nvcc}
# 	export LD_LIBRARY_PATH="$CUDA_HOME/lib64/stubs:${LD_LIBRARY_PATH:-}"
# 	export LIBRARY_PATH="$CUDA_HOME/lib64/stubs:${LIBRARY_PATH:-}"
# 	# Allow caller override; otherwise provide a sensible default set
# 	# : "${TORCH_CUDA_ARCH_LIST:=8.6;8.9;9.0}"
# 	: "${TORCH_CUDA_ARCH_LIST:=8.9;9.0}"
# 	export TORCH_CUDA_ARCH_LIST
# 	echo "🔧 TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST} (override by exporting before calling script)"
# 	# Limit parallelism to avoid flaky ninja/ptxas failures on constrained builders
# 	DEFAULT_PARALLEL=${DEFAULT_PARALLEL:-4}
# 	export MAX_JOBS="${MAX_JOBS:-$DEFAULT_PARALLEL}"
# 	export XFORMERS_BUILD_FROM_SOURCE=1
# 	# Silence some intermittent warnings which stop builds in strict envs
# 	export CMAKE_BUILD_PARALLEL_LEVEL=${CMAKE_BUILD_PARALLEL_LEVEL:-$DEFAULT_PARALLEL}

# 	# Quick sanity check: ensure the installed torch wheel is a CUDA build.
# 	# On a GPU-less builder torch.cuda.is_available() will be False, so do NOT rely on it.
# 	python - <<-'PYCHK' || { echo "❌ CUDA-enabled torch wheel not detected. Install a cu* wheel first."; exit 1; }
# 	import torch, sys
# 	ver = torch.__version__
# 	print(f"Torch version: {ver}")
# 	cuda_build = ('+cu' in ver) or (getattr(torch, 'version', None) and getattr(torch.version, 'cuda', None))
# 	if (not cuda_build) or ('+cpu' in ver):
# 	    print("ERROR: Non-CUDA torch wheel (need a cu* build).")
# 	    sys.exit(1)
# 	print(f"torch.version.cuda = {getattr(torch.version, 'cuda', None)}")
# 	print("✅ Detected CUDA-enabled torch wheel (GPU presence not required during image build).")
# 	PYCHK

# 	# Try prebuilt xformers wheel for CUDA 12.8 first (fast-path)
# 	if uv pip install -U --no-cache-dir xformers --index-url https://download.pytorch.org/whl/cu128; then
# 		# Validate that compiled extension can be imported and torch versions align
# 		python - <<-'PYCHK2'
# 		import sys, torch
# 		ok = True
# 		try:
# 			import xformers, xformers._C  # ensure C++/CUDA extension loads
# 			print("xformers version:", getattr(xformers, "__version__", "?"))
# 			print("torch version:", torch.__version__)
# 		except Exception as e:
# 			print("XFORMERS_IMPORT_ERROR:", e)
# 			ok = False
# 		sys.exit(0 if ok else 1)
# 		PYCHK2
# 		if [ $? -eq 0 ]; then
# 			echo "✅ Installed prebuilt xformers wheel with CUDA support (cu128). Skipping source build."
# 			#clean temporal files to make image smaller
# 			rm -rf /tmp/xformers
# 			#clean build artifacts
# 			uv cache clean || true
# 			pip cache purge || true
# 			return 0
# 		fi
# 		echo "ℹ️  Prebuilt xformers did not load CUDA extension; falling back to source build."
# 		uv pip uninstall -y xformers || true
# 	fi

	# Install build dependencies (include pybind11 & packaging helpers)
	uv pip install --upgrade pip
	uv pip install ninja cmake wheel setuptools build pybind11
	# xformers requirements (some may already be satisfied)
	uv pip install -r requirements.txt || true

	echo "🛠  Building xformers wheel (CUDA kernels) ..."
	# Build wheel using PEP 517 via 'python -m build' (works with uv-managed envs)
	python -m build --wheel --no-isolation -o dist || true
	WHEEL=$(ls -1 dist/xformers-*.whl 2>/dev/null | head -n1 || true)
	if [ -z "$WHEEL" ]; then
		echo "⚠️  PEP 517 build failed, falling back to setup.py bdist_wheel"
		python setup.py bdist_wheel
		WHEEL=$(ls -1 dist/xformers-*.whl 2>/dev/null | head -n1 || true)
	fi
	if [ -z "$WHEEL" ]; then
		echo "❌ Failed to produce xformers wheel"; exit 1; fi
	echo "📦 Built wheel: $WHEEL"

	uv pip install --force-reinstall "$WHEEL"

	echo "🔍 Post-install capability check (python -m xformers.info)"
	if python -m xformers.info 2>/dev/null | grep -qi 'memory_efficient_attention'; then
		python -m xformers.info || true
	else
		echo "⚠️  Could not retrieve xformers.info output (may be limited in build environment)."
	fi

	# Better cleanup (retain installed wheel only)
	cd /
	rm -rf /tmp/xformers
	uv pip uninstall ninja cmake wheel setuptools build pybind11 -y || true  # Remove build deps
}

build_source_builds_main "$@"
