# -----------------------------------------------------------------------------
# Stage 1: Base with CUDA 12.8 dev tools and cuDNN on Ubuntu 22.04
# -----------------------------------------------------------------------------
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_PREFER_BINARY=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3-pip git wget curl libgl1 libglib2.0-0 \
  && ln -sf /usr/bin/python3.10 /usr/bin/python \
  && ln -sf /usr/bin/pip3 /usr/bin/pip \
  && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# Install ComfyUI CLI and core
RUN pip install --no-cache-dir comfy-cli
RUN yes | comfy --workspace /comfyui install --nvidia

WORKDIR /comfyui

# Python dependencies and Q8 kernel compile
RUN pip install --no-cache-dir runpod requests
RUN pip install --no-cache-dir -U packaging wheel ninja setuptools

COPY q8_kernels_cuda /usr/local/lib/python3.11/dist-packages/q8_kernels_cuda


# Copy and restore snapshot
WORKDIR /
COPY src/extra_model_paths.yaml /comfyui/
COPY src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
COPY snapshot.json /
RUN chmod +x /start.sh /restore_snapshot.sh
RUN /restore_snapshot.sh

CMD ["/start.sh"]
