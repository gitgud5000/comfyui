#!/bin/bash

# Source builds for ComfyUI - xformers, SageAttention, and infinite-image-browsing
# This script builds libraries from source for optimal performance
set -euo pipefail

build_source_builds_main() {
    echo "🔨 Building libraries from source..."
    # Install uv for faster package management if not already installed
    $COMFYUI_VENV_PIP install uv
    source "$COMFYUI_VENV/bin/activate"

    uv pip install --upgrade pip

    echo "🔄 Rebuilding libraries Torch"
    build_source_torch_setup
    echo "🔄 Rebuilding libraries Xformers"
    # build_source_triton
    echo "🔄 Rebuilding libraries SageAttention"
    build_source_sageattention
    cleanup_build_artifacts
    
    echo "✅ Source builds completed!"
}

build_source_triton() {
    echo "🚀 Building Triton from source..."
    
    # Activate the virtual environment
    source "$COMFYUI_VENV/bin/activate"
    
    cd /tmp  # Use /tmp instead of /opt
    git clone https://github.com/triton-lang/triton.git
    cd triton

    uv pip install -r python/requirements.txt # build-time dependencies
    uv pip install -e .
}

build_source_torch_setup() {
    echo "🔥 Setting up PyTorch ${PYTORCH_VERSION} with CUDA support..."
    
    # Activate the virtual environment for uv to detect it properly
    source "$COMFYUI_VENV/bin/activate"

    # Uninstall existing torch packages and reinstall with specific versions
    uv pip uninstall torch torchvision torchaudio xformers || true
    uv pip install torch==2.9.0.dev20250716+cu128 torchvision==0.24.0.dev20250716+cu128 torchaudio==2.8.0.dev20250716+cu128 --index-url https://download.pytorch.org/whl/nightly/cu128 --no-cache-dir --force-reinstall
    # uv pip install --pre torch=="${PYTORCH_VERSION}" torchvision \
    #   --index-url https://download.pytorch.org/whl/cu128 \
    #   --no-cache-dir --force-reinstall
    # uv pip install --pre torch torchvision --index-url https://download.pytorch.org/whl/nightly/cu128 --no-cache-dir --force-reinstall
    # uv pip install --pre torch=="${PYTORCH_VERSION}" torchvision torchaudio \
    #     --index-url https://download.pytorch.org/whl/cu128
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

build_source_sageattention() {
    # 1) SM list (e.g. "8.9;12.0"), default → 8.9;12.0
    # local GPU_ARCH_LIST="${1:-8.9;9.0}"
    local GPU_ARCH_LIST="${1:-12.0}"
    echo "🧠 Building SageAttention for SMs [${GPU_ARCH_LIST}]..."

    # 2) Activate venv and force CUDA-path even on GPU-less host
    source "$COMFYUI_VENV/bin/activate"
    export TORCH_CUDA_ARCH_LIST="${GPU_ARCH_LIST}"
    export FORCE_CUDA=1

    # 3) Clone fresh
    cd /tmp && rm -rf SageAttention  # Use /tmp instead of /opt
    git clone --depth=1 https://github.com/thu-ml/SageAttention
    cd SageAttention

    # 4) Apply upstream PR #189 patch
    # echo "🔧 Applying PR #189 patch to setup.py…"
    # curl -sL https://github.com/thu-ml/SageAttention/pull/189.patch \
    #     | patch -p1
    # echo "🔧 Applying PR #160 patch to setup.py…"
    # curl -sL https://github.com/thu-ml/SageAttention/pull/160.patch \
    #     | patch -p1
    echo "🔧 Applying PR #147 patch to setup.py…"
    curl -sL https://github.com/thu-ml/SageAttention/pull/147.patch \
        | patch -p1

    # export EXT_PARALLEL=2 NVCC_APPEND_FLAGS="--threads 2" MAX_JOBS=2 # parallel compiling (Optional)

    echo "🔨 Starting SageAttention build..."
    
    if python setup.py install 2>&1 | tee build.log; then
        echo "✅ SageAttention build completed successfully"
    else
        echo "❌ SageAttention build failed!"
        echo "📋 Last 20 lines of build output:"
        tail -n20 build.log || echo "No build log available"
        echo "💡 Common fixes:"
        echo "  - Check CUDA toolkit is installed"
        echo "  - Verify TORCH_CUDA_ARCH_LIST=${GPU_ARCH_LIST}"
        echo "  - Ensure sufficient disk space"
        exit 1
    fi

    # 6) Cleanup
    cd / && rm -rf /tmp/SageAttention

    echo "✅ SageAttention built for SMs [${GPU_ARCH_LIST}]"
}

build_source_builds_main "$@"
