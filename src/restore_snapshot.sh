#!/usr/bin/env bash
set -e

SNAPSHOT_FILE=$(ls /*snapshot*.json 2>/dev/null | head -n 1)

if [ -z "$SNAPSHOT_FILE" ]; then
    echo "runpod-worker-comfy: No snapshot file found. Exiting..."
    exit 0
fi

echo "runpod-worker-comfy: restoring snapshot: $SNAPSHOT_FILE"

# Restore nodes + install pip deps from snapshot
comfy --workspace /comfyui node restore-snapshot "$SNAPSHOT_FILE" --pip-non-url

# Safety net: ensure cv2 is available
python3 -c "import cv2" || pip install opencv-python 
 pip install -U torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
 pip install -U packaging wheel ninja setuptools
 pip install --no-build-isolation git+https://github.com/Lightricks/LTX-Video-Q8-Kernels.git

echo "runpod-worker-comfy: snapshot restored and OpenCV verified"
