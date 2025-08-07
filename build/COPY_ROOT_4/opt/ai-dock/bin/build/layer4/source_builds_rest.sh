#!/bin/bash

# Source builds for ComfyUI - xformers, SageAttention, and infinite-image-browsing
# This script builds libraries from source for optimal performance
set -e

build_source_builds_main() {
    echo "🔨 Building libraries from source..."
    echo "🔄 Building IIB from source..."
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
