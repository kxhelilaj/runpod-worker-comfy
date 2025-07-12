# Dockerfile for "Wan" GGUF Worker (v2 - More Robust)
#
# This Dockerfile creates a LEAN image. It does NOT download large models.
# It uses a robust loop to install all custom node dependencies and adds ffmpeg.
#

# =====================================================================================
# Stage 1: The 'base' image with all code and dependencies installed.
# =====================================================================================
FROM nvidia/cuda:12.5.1-cudnn-runtime-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python 3.11 and core system tools.
# *** FIX 1: Added ffmpeg for VideoHelperSuite ***
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3-pip \
    git \
    wget \
    curl \
    aria2 \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
  && ln -sf /usr/bin/python3.11 /usr/bin/python \
  && ln -sf /usr/bin/pip3 /usr/bin/pip \
  && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install ComfyUI into the system Python environment.
RUN pip install --no-cache-dir comfy-cli
RUN /usr/bin/yes | comfy --workspace /comfyui install --nvidia
WORKDIR /comfyui

# Install base Python packages for the worker.
RUN pip install --no-cache-dir -U runpod requests

# Add YOUR application code and scripts from the 'src' directory.
WORKDIR /
ADD src/extra_model_paths.yaml /comfyui/
ADD src/start.sh src/restore_snapshot.sh src/download_models.sh src/rp_handler.py test_input.json ./
ADD snapshot.json /
RUN chmod +x /start.sh /restore_snapshot.sh /download_models.sh

# Restore custom nodes using YOUR snapshot script.
RUN /restore_snapshot.sh

# *** FIX 2: More robust dependency installation loop ***
# This finds and installs requirements for ALL custom nodes, not just one.
RUN --mount=type=cache,target=/root/.cache/pip \
    for dir in /comfyui/custom_nodes/*/; do \
        if [ -f "${dir}requirements.txt" ]; then \
            echo "Installing dependencies for $(basename "$dir")" && \
            pip install -r "${dir}requirements.txt"; \
        fi; \
    done

# -----------------------------------------------------------------------------
# Set the preload hook to run our new downloader script at container start.
# -----------------------------------------------------------------------------
ENV RUNPOD_WORKER_PRELOAD=/download_models.sh

# -----------------------------------------------------------------------------
# Final setup and default entrypoint.
# -----------------------------------------------------------------------------
WORKDIR /
CMD ["/start.sh"]