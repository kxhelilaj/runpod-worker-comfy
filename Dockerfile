# ==============================================================================
# STAGE 1: Base build with ComfyUI & all dependencies
# ==============================================================================
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# ------------------------------------------------------------------------------
# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3-pip git wget curl aria2 ffmpeg \
    libgl1 libglib2.0-0 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# ComfyUI CLI
RUN pip install --no-cache-dir comfy-cli
RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 11.8 --nvidia --version 0.2.7

# ------------------------------------------------------------------------------
# Base Python packages
RUN pip install --no-cache-dir runpod requests

# ------------------------------------------------------------------------------
# Copy your application scripts & restore nodes
WORKDIR /
COPY src/extra_model_paths.yaml /comfyui/
COPY src/start.sh src/restore_snapshot.sh src/download_models.sh src/rp_handler.py test_input.json ./
COPY snapshot.json /
RUN chmod +x /start.sh /restore_snapshot.sh /download_models.sh

# Restore custom nodes via snapshot
RUN /restore_snapshot.sh

# ------------------------------------------------------------------------------
# Install all requirements from custom nodes robustly
RUN find /comfyui/custom_nodes -type f -name 'requirements.txt' -exec pip install -r {} \; || true

# ==============================================================================
# STAGE 2: Downloader to download all large models
# ==============================================================================
FROM base AS downloader

# Pre-create all needed folders
RUN mkdir -p \
    /comfyui/models/loras/wan \
    /comfyui/models/vae/nativewan \
    /comfyui/models/unets \
    /comfyui/models/clip/native

# Copy your download script
COPY src/download_models.sh /download_models.sh
RUN chmod +x /download_models.sh

# Execute downloads in the build step (so layers are cached)
RUN /download_models.sh

# ==============================================================================
# STAGE 3: Final runtime image, with just binaries + downloaded models
# ==============================================================================
FROM base AS final

# Copy models from downloader stage
COPY --from=downloader /comfyui/models /comfyui/models

# Set preload to download script (can still run if needed, but models already there)
ENV RUNPOD_WORKER_PRELOAD=/download_models.sh

# Final entrypoint
CMD ["/start.sh"]
