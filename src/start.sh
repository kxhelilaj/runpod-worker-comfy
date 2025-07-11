#!/usr/bin/env bash
set -e

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
        curl -fsSL -o "$dest" "$url" || echo "❌ Failed to download: $url"
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
# Install Q8 kernels at runtime if not installed (GPU must be visible)
# -----------------------------------------------------------------------------

echo "runpod-worker-comfy: Checking for Q8 kernels..."

# if python3 -c "import q8_kernels" 2>/dev/null; then
#     echo "✅ Q8 kernels already installed."
# else
#     echo "⬇️ Installing Q8 kernels at runtime..."
#     TORCH_CUDA_ARCH_LIST="8.0 8.6 8.9 9.0" \
#     pip install --no-cache-dir --no-build-isolation \
#         git+https://github.com/Lightricks/LTX-Video-Q8-Kernels.git@f3066edea210082799ca5a2bbf9ef0321c5dd8fc || \
#         echo "⚠️  Q8 kernel install failed — continuing without them."
# fi

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
