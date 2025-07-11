#!/usr/bin/env bash
set -e

echo "--- [RUNPOD_WORKER_PRELOAD] ---"
echo "Checking & downloading required models for the 'Wan' workflow..."

# A robust function to download a file if it doesn't exist.
download_file() {
    local url="$1"
    local dest="$2"
    
    if [ ! -f "$dest" ]; then
        echo "⬇️  Downloading: $(basename "$dest")"
        # Create the directory path if it doesn't exist.
        mkdir -p "$(dirname "$dest")"
        # Use aria2c for fast, multi-connection downloads. Fallback to curl on failure.
        aria2c -c -x 16 -s 16 -k 1M -d "$(dirname "$dest")" -o "$(basename "$dest")" "$url" || \
        (echo "⚠️  aria2c failed, falling back to curl..." && curl -fsSL -o "$dest" "$url") || \
        echo "❌ FATAL: Failed to download: $url"
    else
        echo "✅ Found cached: $(basename "$dest")"
    fi
}

# --- Download LoRAs ---
download_file "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors" "/comfyui/models/loras/wan/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors"
download_file "https://huggingface.co/alibaba-pai/Wan2.1-Fun-Reward-LoRAs/resolve/main/Wan2.1-Fun-14B-InP-MPS.safetensors" "/comfyui/models/loras/wan/Wan2.1-Fun-14B-InP-MPS.safetensors"
download_file "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_AccVid_I2V_480P_14B_lora_rank32_fp16.safetensors" "/comfyui/models/loras/wan/Wan21_AccVid_I2V_480P_14B_lora_rank32_fp16.safetensors"
download_file "https://huggingface.co/vrgamedevgirl84/Wan14BT2VFusioniX/resolve/main/OtherLoRa's/Wan14B_RealismBoost.safetensors" "/comfyui/models/loras/wan/Wan14B_RealismBoost.safetensors"
download_file "https://huggingface.co/vrgamedevgirl84/Wan14BT2VFusioniX/resolve/main/OtherLoRa's/DetailEnhancerV1.safetensors" "/comfyui/models/loras/wan/DetailEnhancerV1.safetensors"

# --- Download VAE ---
download_file "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "/comfyui/models/vae/nativewan/wan_2.1_vae.safetensors"

# --- Download Unet (GGUF) ---
download_file "https://huggingface.co/city96/Wan2.1-I2V-14B-720P-gguf/resolve/main/wan2.1-i2v-14b-720p-Q3_K_M.gguf" "/comfyui/models/unets/wan2.1-i2v-14b-720p-Q3_K_M.gguf"

# --- Download CLIP (GGUF) ---
download_file "https://huggingface.co/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q8_0.gguf" "/comfyui/models/clip/native/umt5-xxl-encoder-Q8_0.gguf"

echo "✅ Model check complete."