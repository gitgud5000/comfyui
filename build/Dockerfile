# For build automation - Allows building from any ai-dock base image
# Use a *cuda*base* image as default because pytorch brings the libs
ARG IMAGE_BASE="ghcr.io/gitgud5000/python:py312"
FROM ${IMAGE_BASE}

LABEL org.opencontainers.image.source https://github.com/gitgud5000/comfyui
LABEL org.opencontainers.image.description "ComfyUI with CUDA 12.8.1 support for RTX 5090 and PyTorch 2.7.0"
LABEL maintainer="GitGud5000"

ENV COMFYUI_VENV=$VENV_DIR/comfyui
ENV COMFYUI_VENV_PYTHON=$COMFYUI_VENV/bin/python
ENV COMFYUI_VENV_PIP=$COMFYUI_VENV/bin/pip

ENV API_VENV=$VENV_DIR/api
ENV API_VENV_PYTHON=$API_VENV/bin/python
ENV API_VENV_PIP=$API_VENV/bin/pip

ENV IMAGE_SLUG="comfyui"
ENV OPT_SYNC=ComfyUI

# Prepare environment
ARG PYTHON_VERSION="3.12"
ENV PYTHON_VERSION=${PYTHON_VERSION}
ARG PYTORCH_VERSION="2.7.0"
ENV PYTORCH_VERSION="${PYTORCH_VERSION}"
COPY --chown=0:1111 ./COPY_ROOT_0/ /
ARG IMAGE_BASE
RUN set -eo pipefail && /opt/ai-dock/bin/build/layer0/init.sh | tee /var/log/build.log

RUN echo "bust cache"
# Install full CUDA toolkit for building, then remove it after compilation
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        cuda-toolkit-12-8 && \
    ln -s /usr/local/cuda-12.8 /usr/local/cuda || true && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install software (includes SageAttention compilation)
ARG COMFYUI_BUILD_REF
ENV COMFYUI_BUILD_REF=${COMFYUI_BUILD_REF}
COPY --chown=0:1111 ./COPY_ROOT_1/ /
RUN set -eo pipefail && /opt/ai-dock/bin/build/layer1/init.sh | tee -a /var/log/build.log
# RUN chmod +x /opt/ai-dock/bin/build/layer1/source_builds.sh && \
    # set -eo pipefail && /opt/ai-dock/bin/build/layer1/source_builds.sh | tee -a /var/log/build.log

RUN apt-get update && \
    apt-get install -y gcc-10 g++-10 && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 100

RUN apt-get update && \
    apt-get install -y gcc-12 g++-12 && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 120

# Ensure uv is available in the comfyui virtual environment before source builds
RUN set -eo pipefail \
    && echo "Installing uv into $COMFYUI_VENV" \
    && $COMFYUI_VENV_PIP install -U uv \
    && $COMFYUI_VENV/bin/uv --version || true
# Build source libraries Xformers
COPY --chown=0:1111 ./COPY_ROOT_3/ /
RUN chmod +x /opt/ai-dock/bin/build/layer3/source_builds_xformers.sh  && \
    set -eo pipefail && /opt/ai-dock/bin/build/layer3/source_builds_xformers.sh | tee -a /var/log/build.log
    
# Build source libraries SageAttention
COPY --chown=0:1111 ./COPY_ROOT_2/ /
RUN chmod +x /opt/ai-dock/bin/build/layer2/source_builds_sageattn.sh  && \
    set -eo pipefail && /opt/ai-dock/bin/build/layer2/source_builds_sageattn.sh | tee -a /var/log/build.log

# Build remaining source libraries
COPY --chown=0:1111 ./COPY_ROOT_4/ /
RUN chmod +x /opt/ai-dock/bin/build/layer4/source_builds_rest.sh  && \
    set -eo pipefail && /opt/ai-dock/bin/build/layer4/source_builds_rest.sh | tee -a /var/log/build.log


# Remove CUDA toolkit after compilation to save space (keep only runtime)
RUN apt-get update && \
    apt-get remove -y cuda-toolkit-12-8 && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# Remove compilers and related alternatives after build to reduce image size
# RUN apt-get update && \
#     apt-get purge -y gcc-10 g++-10 && \
#     update-alternatives --remove gcc /usr/bin/gcc-10 || true && \
#     update-alternatives --remove g++ /usr/bin/g++-10 || true && \
#     update-alternatives --auto gcc || true && \
#     update-alternatives --auto g++ || true && \
#     apt-get autoremove -y --purge && \
#     apt-get clean && \
#     rm -rf /var/lib/apt/lists/* /var/cache/apt/* /root/.cache/pip || true

# Copy overrides and models into later layers for fast rebuilds
COPY --chown=0:1111 ./COPY_ROOT_99/ /
RUN set -eo pipefail && /opt/ai-dock/bin/build/layer99/init.sh | tee -a /var/log/build.log
ENV PYTHON_DEFAULT_VENV=comfyui

# Keep init.sh as-is and place additional logic in /opt/ai-dock/bin/preflight.d
CMD ["init.sh"]
