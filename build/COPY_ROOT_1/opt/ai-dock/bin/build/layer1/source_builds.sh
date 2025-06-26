#!/bin/false

# Source builds for ComfyUI - xformers, SageAttention, and infinite-image-browsing
# This script builds libraries from source for optimal performance

build_source_builds_main() {
    echo "🔨 Building libraries from source..."
    
    # Install uv for faster package management if not already installed
    $COMFYUI_VENV_PIP install uv
    
    build_source_sageattention
    build_source_torch_setup
    build_source_xformers
    build_source_infinite_browsing
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

build_source_torch_setup() {
    echo "🔥 Setting up PyTorch ${PYTORCH_VERSION} with CUDA support..."
    
    # Activate the virtual environment for uv to detect it properly
    source "$COMFYUI_VENV/bin/activate"
    
    # Uninstall existing torch packages and reinstall with specific versions
    uv pip uninstall torch torchvision torchaudio xformers || true
    uv pip install --pre torch=="${PYTORCH_VERSION}" torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu128
}

build_source_xformers() {
    echo "🚀 Building xformers from source..."
    
    # Activate the virtual environment
    source "$COMFYUI_VENV/bin/activate"
    
    cd /tmp  # Use /tmp instead of /opt
    git clone --recursive https://github.com/facebookresearch/xformers.git
    cd xformers
    
    # Install build dependencies
    uv pip install ninja cmake wheel
    uv pip install -r requirements.txt
    
    # Build and install xformers
    python setup.py bdist_wheel
    uv pip install dist/*.whl
    
    # Better cleanup
    cd /
    rm -rf /tmp/xformers
    uv pip uninstall ninja cmake wheel -y || true  # Remove build deps
}

build_source_sageattention() {
    # 1) SM list (e.g. "8.9;12.0"), default → 8.9;12.0
    local GPU_ARCH_LIST="${1:-8.9;12.0}"
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
    echo "🔧 Applying PR #189 patch to setup.py…"
    curl -sL https://github.com/thu-ml/SageAttention/pull/189.patch \
      | patch -p1

    # 5) Build & install
    python setup.py install

    # 6) Cleanup
    cd / && rm -rf /tmp/SageAttention

    echo "✅ SageAttention built for SMs [${GPU_ARCH_LIST}]"
}





build_source_infinite_browsing() {
    echo "🖼️ Installing infinite image browsing..."
    
    # Activate the virtual environment
    source "$COMFYUI_VENV/bin/activate"
    
    cd /opt/  # Clone directly to /opt since whole repo is needed
    git clone https://github.com/zanllp/sd-webui-infinite-image-browsing.git 
    cd sd-webui-infinite-image-browsing
    
    # Install requirements
    uv pip install -r requirements.txt
    
    # Keep the whole directory as it's needed at runtime (app.py is just the launcher)
    echo "Infinite image browsing installed in /opt/sd-webui-infinite-image-browsing"
}

build_source_builds_main "$@"
