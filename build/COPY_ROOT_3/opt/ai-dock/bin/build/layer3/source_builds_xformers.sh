#!/bin/bash

# Source builds for ComfyUI - xformers, SageAttention, and infinite-image-browsing
# This script builds libraries from source for optimal performance
set -e

build_source_builds_main() {
    echo "🔨 Building libraries from source..."
    
    # Install uv for faster package management if not already installed
    $COMFYUI_VENV_PIP install uv
    
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

build_source_builds_main "$@"
