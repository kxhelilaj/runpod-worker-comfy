# Dockerfile for LTX-Video Worker with Q8 Kernels
#
# This Dockerfile is built on a modern CUDA base to meet the requirements
# of the LTX-Video-Q8-Kernels library. It uses best practices to ensure a
# clean, efficient, and error-free build.
#

# -----------------------------------------------------------------------------
# Stage 1: Use a modern CUDA 12.5 base image.
# NOTE: The Q8-Kernels library requires a host system with NVIDIA drivers
# compatible with CUDA 12.8+, but the container toolkit can be slightly
# older. CUDA 12.5.1 is the latest stable release and fully supports this.
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
# Install comfy-cli first.
RUN pip install --no-cache-dir comfy-cli

# Install ComfyUI. We remove the `--cuda-version` flag to let it automatically
# use the newer toolkit from our base image. This is more robust.
RUN /usr/bin/yes | comfy --workspace /comfyui install --nvidia

# Set the working directory for subsequent commands.
WORKDIR /comfyui

# -----------------------------------------------------------------------------
# Install all additional Python packages in a SINGLE, CLEAN layer.
# This solves the "out of space" error by not installing torch twice.
# -----------------------------------------------------------------------------
RUN pip install runpod requests
RUN pip install --no-cache-dir -U packaging wheel ninja setuptools && \
    pip install --no-cache-dir --no-build-isolation git+https://github.com/Lightricks/LTX-Video-Q8-Kernels.git

# -----------------------------------------------------------------------------
# Add application code, scripts, and restore custom nodes.
# -----------------------------------------------------------------------------
# Add extra config for model paths.
ADD src/extra_model_paths.yaml ./

# Go back to the root for subsequent commands.
WORKDIR /

# Add application scripts and snapshot definition.
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
ADD snapshot.json /
RUN chmod +x /start.sh /restore_snapshot.sh

# Restore your custom nodes from the snapshot.
RUN /restore_snapshot.sh

# -----------------------------------------------------------------------------
# Final setup and default entrypoint.
# -----------------------------------------------------------------------------
# Set the working directory back to root.
WORKDIR /
# Default entrypoint for the container.
CMD ["/start.sh"]