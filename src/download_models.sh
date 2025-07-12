#!/usr/bin/env bash
set -e
set -x  # debug

echo "--- [RUNPOD_WORKER_PRELOAD] ---"
echo "Checking & downloading required models for the 'Wan' workflow..."

download_file() {
    local url="$1"
    local dest="$2"
    if [ ! -f "$dest" ]; then
        echo "⬇️  Downloading: $dest"
        mkdir -p "$(dirname "$dest")"
        aria2c -c -x 16 -s 16 -k 1M -d "$(dirname "$dest")" -o "$(basename "$dest")" "$url" || \
        curl -fsSL -o "$dest" "$url" || \
        echo "❌ Failed to download: $url"
    else
        echo "✅ Found cached: $dest"
    fi
}

# --- LORAs ---
download_file "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors" "/comfyui/models/loras/wan/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors"
download_file "https://huggingface.co/alibaba-pai/Wan2.1-Fun-Reward-LoRAs/resolve/main/Wan2.1-Fun-14B-InP-MPS.safetensors" "/comfyui/models/loras/wan/Wan2.1-Fun-14B-InP-MPS_reward_lora_comfy.safetensors"
download_file "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_AccVid_I2V_480P_14B_lora_rank32_fp16.safetensors" "/comfyui/models/loras/wan/Wan21_AccVid_I2V_480P_14B_lora_rank32_fp16.safetensors"
download_file "https://huggingface.co/vrgamedevgirl84/Wan14BT2VFusioniX/resolve/main/OtherLoRa's/Wan14B_RealismBoost.safetensors" "/comfyui/models/loras/wan/Wan14B_RealismBoost.safetensors"
download_file "https://huggingface.co/vrgamedevgirl84/Wan14BT2VFusioniX/resolve/main/OtherLoRa's/DetailEnhancerV1.safetensors" "/comfyui/models/loras/wan/DetailEnhancerV1.safetensors"

# --- VAE ---
download_file "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "/comfyui/models/vae/nativewan/wan_2.1_vae.safetensors"

# --- UNET GGUF ---
download_file "https://huggingface.co/city96/Wan2.1-I2V-14B-720P-gguf/resolve/main/wan2.1-i2v-14b-720p-Q3_K_M.gguf" "/comfyui/models/unet/wan2.1-i2v-14b-720p-Q3_K_M.gguf"

# --- CLIP GGUF ---
download_file "https://huggingface.co/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q8_0.gguf" "/comfyui/models/clip/native/umt5-xxl-encoder-Q8_0.gguf"

# ✅ Verify paths
echo "Downloaded files:"
ls -Rlh /comfyui/models || true
