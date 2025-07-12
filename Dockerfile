# ============================================================================
# Stage 1: Base with ComfyUI + dependencies
# ============================================================================
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04 as base

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_PREFER_BINARY=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

# --- Core system deps ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3-pip git wget curl aria2 ffmpeg libgl1 libglib2.0-0 \
 && ln -sf /usr/bin/python3.10 /usr/bin/python \
 && ln -sf /usr/bin/pip3 /usr/bin/pip \
 && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# --- Install comfy-cli + ComfyUI ---
RUN pip install --no-cache-dir comfy-cli
RUN yes | comfy --workspace /comfyui install --nvidia

# --- Core Python deps ---
WORKDIR /comfyui
RUN pip install --no-cache-dir runpod requests

# ============================================================================
# Stage 2: Download all required models
# ============================================================================
FROM base as downloader

# Add model downloader script
WORKDIR /
COPY src/download_models.sh /download_models.sh
RUN chmod +x /download_models.sh

# Run model download script
RUN bash /download_models.sh

# ============================================================================
# Stage 3: Final clean image
# ============================================================================
FROM base as final

WORKDIR /

# --- Copy everything needed ---
COPY src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
COPY snapshot.json /
COPY src/extra_model_paths.yaml /comfyui/
RUN chmod +x /start.sh /restore_snapshot.sh

# --- Restore snapshot (custom nodes) ---
RUN /restore_snapshot.sh

# --- Install all custom node requirements ---
RUN if [ -d /comfyui/custom_nodes ]; then \
      for dir in /comfyui/custom_nodes/*; do \
        [ -f "$dir/requirements.txt" ] && pip install -r "$dir/requirements.txt"; \
      done \
    ; fi

# --- Copy models from downloader ---
COPY --from=downloader /comfyui/models /comfyui/models

# Default entrypoint
CMD ["/start.sh"]
