# ================================================================================
# Dockerfile for ComfyUI "Wan" GGUF Worker with Snapshot & Runtime Model Support
# ================================================================================

FROM nvidia/cuda:12.5.1-cudnn-runtime-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_PREFER_BINARY=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# ------------------------------------------------------------------------------
# System Packages & Python
# ------------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 python3-pip git wget curl aria2 ffmpeg \
    libgl1 libglib2.0-0 \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# Install ComfyUI + CLI
# ------------------------------------------------------------------------------
RUN pip install --no-cache-dir comfy-cli

RUN /usr/bin/yes | comfy --workspace /comfyui install --nvidia

WORKDIR /comfyui

# ------------------------------------------------------------------------------
# Install Required Python Dependencies
# ------------------------------------------------------------------------------
RUN pip install --no-cache-dir -U runpod requests imageio-ffmpeg

# ------------------------------------------------------------------------------
# Add Your Scripts, Snapshot & Configs
# ------------------------------------------------------------------------------
WORKDIR /

ADD src/extra_model_paths.yaml /comfyui/
ADD src/start.sh src/restore_snapshot.sh src/download_models.sh src/rp_handler.py test_input.json ./
ADD snapshot.json /

RUN chmod +x /start.sh /restore_snapshot.sh /download_models.sh

# ------------------------------------------------------------------------------
# Restore custom nodes using snapshot
# ------------------------------------------------------------------------------
RUN /restore_snapshot.sh

# ------------------------------------------------------------------------------
# Install requirements.txt from all /custom_nodes/*/requirements.txt
# ------------------------------------------------------------------------------
RUN --mount=type=cache,target=/root/.cache/pip \
    for dir in /comfyui/custom_nodes/*/; do \
        if [ -f "${dir}requirements.txt" ]; then \
            echo "Installing dependencies for $(basename "$dir")..." && \
            pip install -r "${dir}requirements.txt"; \
        fi; \
    done

# ------------------------------------------------------------------------------
# Download models at runtime via hook
# ------------------------------------------------------------------------------
ENV RUNPOD_WORKER_PRELOAD=/download_models.sh
RUN ./download_models.sh

# ------------------------------------------------------------------------------
# Entry Point
# ------------------------------------------------------------------------------
CMD ["/start.sh"]
