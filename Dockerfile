# =============================================================================
# Stage 1: Build base with Python + ComfyUI
# =============================================================================
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04 as base

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_PREFER_BINARY=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

# --- System dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3-pip git wget curl aria2 ffmpeg libgl1 libglib2.0-0 \
 && ln -sf /usr/bin/python3.10 /usr/bin/python \
 && ln -sf /usr/bin/pip3 /usr/bin/pip \
 && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# --- Python deps ---
RUN pip install --no-cache-dir comfy-cli

# --- Install ComfyUI ---
RUN yes | comfy --workspace /comfyui install --nvidia
WORKDIR /comfyui
RUN pip install --no-cache-dir runpod requests

# --- Add core scripts and config ---
WORKDIR /
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
ADD snapshot.json /
ADD src/extra_model_paths.yaml /comfyui/
RUN chmod +x /start.sh /restore_snapshot.sh

# --- Restore ComfyUI snapshot to get all custom nodes ---
RUN /restore_snapshot.sh

# --- Install all node requirements if present ---
RUN --mount=type=cache,target=/root/.cache/pip \
  for d in /comfyui/custom_nodes/*; do \
    [ -f "$d/requirements.txt" ] && pip install -r "$d/requirements.txt"; \
  done


# =============================================================================
# Stage 2: Download models with aria2
# =============================================================================
FROM base as downloader

WORKDIR /comfyui

# RUN mkdir -p models/loras/wan models/vae/nativewan models/unets models/clip/native

# --- Download model files ---
RUN /download_models.sh

# =============================================================================
# Stage 3: Final image - lean and ready
# =============================================================================
FROM base as final

# Copy models from downloader stage
COPY --from=downloader /comfyui/models /comfyui/models

# Set default startup
CMD ["/start.sh"]
