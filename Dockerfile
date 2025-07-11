# Dockerfile for LTX-Video Worker with Q8 Kernels
#
# This Dockerfile is built on a modern CUDA base to meet the requirements
# of the LTX-Video-Q8-Kernels library. It uses best practices to ensure a
# clean, efficient, and error-free build.
#

# -----------------------------------------------------------------------------
# Stage 1: Use a modern CUDA 12.5 base image.
# -----------------------------------------------------------------------------
FROM nvidia/cuda:12.5.1-cudnn-runtime-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# -----------------------------------------------------------------------------
# Install Python and core system tools in a single layer.
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3-pip \
    git \
    wget \
    curl \
    libgl1 \
    libglib2.0-0 \
  && ln -sf /usr/bin/python3.10 /usr/bin/python \
  && ln -sf /usr/bin/pip3 /usr/bin/pip \
  && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install ComfyUI. It will detect the base image's CUDA version.
# -----------------------------------------------------------------------------
RUN pip install --no-cache-dir comfy-cli

RUN /usr/bin/yes | comfy --workspace /comfyui install --nvidia

WORKDIR /comfyui

# -----------------------------------------------------------------------------
# Install all additional Python packages, including the Q8 Kernels.
# -----------------------------------------------------------------------------
# This is the corrected command.
# We set TORCH_CUDA_ARCH_LIST to prevent the build script from needing a live GPU.
# This tells it to build for common Ampere & Hopper/Ada architectures (30-series, 40-series, A100, H100).

RUN pip install runpod requests
RUN pip install --no-cache-dir -U packaging wheel ninja setuptools && \
    TORCH_CUDA_ARCH_LIST="8.0 8.6 8.9 9.0" \
    pip install --no-cache-dir --no-build-isolation git+https://github.com/Lightricks/LTX-Video-Q8-Kernels.git

# -----------------------------------------------------------------------------
# Add application code, scripts, and restore custom nodes.
# -----------------------------------------------------------------------------
ADD src/extra_model_paths.yaml ./

WORKDIR /

ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
ADD snapshot.json /
RUN chmod +x /start.sh /restore_snapshot.sh

RUN /restore_snapshot.sh

# -----------------------------------------------------------------------------
# Final setup and default entrypoint.
# -----------------------------------------------------------------------------
WORKDIR /
CMD ["/start.sh"]