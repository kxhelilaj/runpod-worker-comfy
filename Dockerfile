# =====================================================================================
# Stage 1: Build ComfyUI + all dependencies
# =====================================================================================
FROM nvidia/cuda:12.2.0-cudnn8-runtime-ubuntu22.04 as base

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3-pip git wget curl aria2 ffmpeg \
    libgl1 libglib2.0-0 \
 && ln -sf /usr/bin/python3.10 /usr/bin/python \
 && ln -sf /usr/bin/pip3 /usr/bin/pip \
 && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir comfy-cli runpod requests
RUN /usr/bin/yes | comfy --workspace /comfyui install --nvidia

# -------------------------------------------------------------------------------------
# Add your custom nodes snapshot
# -------------------------------------------------------------------------------------
WORKDIR /
ADD snapshot.json /
ADD src/extra_model_paths.yaml /comfyui/
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

RUN /restore_snapshot.sh

# Install ALL custom node requirements (loop)
RUN for dir in /comfyui/custom_nodes/*; do \
      [ -f "$dir/requirements.txt" ] && pip install -r "$dir/requirements.txt"; \
    done || true

# -------------------------------------------------------------------------------------
# Final image only needs runtime downloader
# -------------------------------------------------------------------------------------
ADD src/download_models.sh /
RUN chmod +x /download_models.sh
ENV RUNPOD_WORKER_PRELOAD=/download_models.sh

WORKDIR /
CMD ["/start.sh"]
