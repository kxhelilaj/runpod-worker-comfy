# -----------------------------------------------------------------------------
# Dockerfile for ComfyUI LTX-Video Worker with Q8 Kernels Support
# -----------------------------------------------------------------------------

# CUDA base image with nvcc support (required for Q8 build)
FROM nvidia/cuda:12.5.1-cudnn8-devel-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_PREFER_BINARY=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# -----------------------------------------------------------------------------
# System dependencies
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
# Install ComfyUI CLI & base setup
# -----------------------------------------------------------------------------
RUN pip install --no-cache-dir comfy-cli
RUN /usr/bin/yes | comfy --workspace /comfyui install --nvidia

# -----------------------------------------------------------------------------
# Install Python dependencies and Q8 kernels
# -----------------------------------------------------------------------------
RUN pip install --no-cache-dir runpod requests
RUN pip install --no-cache-dir -U packaging wheel ninja setuptools

# Build Q8 kernels using dummy arch list (no GPU needed during build)
RUN TORCH_CUDA_ARCH_LIST="8.0 8.6 8.9 9.0" \
    pip install --no-cache-dir --no-build-isolation \
    git+https://github.com/Lightricks/LTX-Video-Q8-Kernels.git@f3066edea210082799ca5a2bbf9ef0321c5dd8fc

# -----------------------------------------------------------------------------
# Copy runtime files, snapshot and restore nodes
# -----------------------------------------------------------------------------
WORKDIR /comfyui
COPY src/extra_model_paths.yaml ./

WORKDIR /
COPY src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
COPY snapshot.json /
RUN chmod +x /start.sh /restore_snapshot.sh

# Restore custom nodes using ComfyUI snapshot
RUN /restore_snapshot.sh

# -----------------------------------------------------------------------------
# Final entrypoint
# -----------------------------------------------------------------------------
CMD ["/start.sh"]
