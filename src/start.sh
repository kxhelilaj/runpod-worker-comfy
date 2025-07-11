#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# -----------------------------------------------------------------------------
# Download models at container runtime (if not already cached)
# -----------------------------------------------------------------------------

echo "runpod-worker-comfy: Checking & downloading required models..."

download_model() {
    local url="$1"
    local dest="$2"
    if [ ! -f "$dest" ]; then
        echo "⬇️  Downloading: $dest"
        mkdir -p "$(dirname "$dest")"
        curl -L -o "$dest" "$url"
    else
        echo "✅ Found cached: $dest"
    fi
}

download_model "https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltxv-13b-0.9.7-dev-fp8.safetensors" \
    "/comfyui/models/checkpoints/ltxv-13b-0.9.7-dev-fp8.safetensors"

download_model "https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltxv-spatial-upscaler-0.9.7.safetensors" \
    "/comfyui/models/upscale_models/ltxv-spatial-upscaler-0.9.7.safetensors"

download_model "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors" \
    "/comfyui/models/clip/t5/t5xxl_fp16.safetensors"

# -----------------------------------------------------------------------------
# Start services
# -----------------------------------------------------------------------------

if [ "$SERVE_API_LOCALLY" == "true" ]; then
    echo "runpod-worker-comfy: Starting ComfyUI"
    python3 /comfyui/main.py --disable-auto-launch --disable-metadata --listen &

    echo "runpod-worker-comfy: Starting RunPod Handler"
    python3 -u /rp_handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    echo "runpod-worker-comfy: Starting ComfyUI"
    python3 /comfyui/main.py --disable-auto-launch --disable-metadata &

    echo "runpod-worker-comfy: Starting RunPod Handler"
    python3 -u /rp_handler.py
fi
