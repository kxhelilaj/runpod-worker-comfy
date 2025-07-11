# Dockerfile for LTX-Video Worker with PRE-BUILT Q8 Kernels (v3 - Correct Path)
#
# This version places the pre-built kernels into the ComfyUI virtual environment,
# which is the correct location for the runtime to find them.
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
# Install Python 3.11 and core system tools.
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3-pip \
    git \
    wget \
    curl \
    libgl1 \
    libglib2.0-0 \
  && ln -sf /usr/bin/python3.11 /usr/bin/python \
  && ln -sf /usr/bin/pip3 /usr/bin/pip \
  && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Install ComfyUI. This creates a virtual environment at /comfyui/venv/
# -----------------------------------------------------------------------------
RUN pip install --no-cache-dir comfy-cli

RUN /usr/bin/yes | comfy --workspace /comfyui install --nvidia

WORKDIR /comfyui

# -----------------------------------------------------------------------------
# Install standard Python packages into the ComfyUI venv.
# -----------------------------------------------------------------------------
RUN . venv/bin/activate && \
    pip install --no-cache-dir -U runpod requests packaging wheel ninja setuptools

# -----------------------------------------------------------------------------
# COPY the pre-built Q8-Kernels into the correct ComfyUI VENV site-packages.
# THIS IS THE KEY FIX.
# -----------------------------------------------------------------------------
COPY q8_kernels_cuda /comfyui/venv/lib/python3.11/site-packages/q8_kernels_cuda

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