# Dockerfile for a Self-Contained "Wan" GGUF Worker
#
# This multi-stage Dockerfile creates a final image with all models and
# dependencies "baked in". It does NOT require any runtime downloads.
#

# =====================================================================================
# Stage 1: The 'base' image with all code and dependencies installed.
# =====================================================================================
FROM nvidia/cuda:12.5.1-cudnn-runtime-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python 3.11 and core system tools, including aria2 for fast downloads.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3-pip \
    git \
    wget \
    curl \
    aria2 \
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

# Add YOUR application code, scripts, and snapshot definition.
WORKDIR /
ADD src/extra_model_paths.yaml /comfyui/
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
ADD snapshot.json /
RUN chmod +x /start.sh /restore_snapshot.sh

# Restore custom nodes using YOUR snapshot script.
RUN /restore_snapshot.sh

# CRITICAL STEP: Install Python dependencies for the restored nodes.
RUN --mount=type=cache,target=/root/.cache/pip \
    if [ -f /comfyui/custom_nodes/ComfyUI-GGUF-Tools/requirements.txt ]; then \
        pip install -r /comfyui/custom_nodes/ComfyUI-GGUF-Tools/requirements.txt; \
    fi

# =====================================================================================
# Stage 2: The 'downloader' stage to fetch all large model files.
# =====================================================================================
FROM base AS downloader

WORKDIR /comfyui/models

# Create all necessary model directories upfront.
RUN mkdir -p loras/wan vae/nativewan unets clip/native

# Download all required models using the fast aria2c tool.
RUN \
    echo "Downloading LoRAs..." && \
    aria2c -x 16 -s 16 -k 1M -d loras/wan -o Wan21_AccVid_I2V_480P_14B_lora_rank32_fp16.safetensors "https://huggingface.co/wavymulder/FusionX-I2V/resolve/main/lora/wan/Wan21_AccVid_I2V_480P_14B_lora_rank32_fp16.safetensors" && \
    aria2c -x 16 -s 16 -k 1M -d loras/wan -o DetailEnhancerV1.safetensors "https://huggingface.co/wavymulder/FusionX-I2V/resolve/main/lora/wan/DetailEnhancerV1.safetensors" && \
    aria2c -x 16 -s 16 -k 1M -d loras/wan -o Wan14B_RealismBoost.safetensors "https://huggingface.co/wavymulder/FusionX-I2V/resolve/main/lora/wan/Wan14B_RealismBoost.safetensors" && \
    aria2c -x 16 -s 16 -k 1M -d loras/wan -o Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors "https://huggingface.co/wavymulder/FusionX-I2V/resolve/main/lora/wan/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors" && \
    aria2c -x 16 -s 16 -k 1M -d loras/wan -o Wan2.1-Fun-14B-InP-MPS_reward_lora_comfy.safetensors "https://huggingface.co/wavymulder/FusionX-I2V/resolve/main/lora/wan/Wan2.1-Fun-14B-InP-MPS_reward_lora_comfy.safetensors" && \
    \
    echo "Downloading VAE..." && \
    aria2c -x 16 -s 16 -k 1M -d vae/nativewan -o wan_2.1_vae.safetensors "https://huggingface.co/wavymulder/FusionX-I2V/resolve/main/vae/nativewan/wan_2.1_vae.safetensors" && \
    \
    echo "Downloading Unet (GGUF)..." && \
    aria2c -x 16 -s 16 -k 1M -d unets -o wan2.1-i2v-14b-720p-q2_k.gguf "https://huggingface.co/lx-s/wan2.1-i2v-14b-720p/resolve/main/wan2.1-i2v-14b-720p-q2_k.gguf" && \
    \
    echo "Downloading CLIP (GGUF)..." && \
    aria2c -x 16 -s 16 -k 1M -d clip/native -o umt5-xxl-encoder-Q8_0.gguf "https://huggingface.co/lx-s/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q8_0.gguf"


# =====================================================================================
# Stage 3: The 'final' image, ready for production.
# =====================================================================================
FROM base AS final

# Copy the downloaded models from the 'downloader' stage into the final image.
COPY --from=downloader /comfyui/models /comfyui/models

# Set the final working directory and default command.
WORKDIR /
CMD ["/start.sh"]