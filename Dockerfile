# -----------------------------------------------------------------------------
# Base image with CUDA 12.2 (compatible with CUDA 12.8 custom nodes)
# -----------------------------------------------------------------------------
  FROM nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 as base

  ENV DEBIAN_FRONTEND=noninteractive
  ENV PIP_PREFER_BINARY=1
  ENV PYTHONUNBUFFERED=1 
  ENV CMAKE_BUILD_PARALLEL_LEVEL=8
  
  # Install Python and core tools
  RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    curl \                
    libgl1 \
    libglib2.0-0 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

  
  RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*
  
  # Install comfy-cli
  RUN pip install comfy-cli
  
  # Install ComfyUI into /comfyui with CUDA 12.2 setup
  RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 12.6 --nvidia 
  
  WORKDIR /comfyui
  
  # Install runpod client + requests
  RUN pip install runpod requests
  RUN pip install -U torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
  RUN pip install -U packaging wheel ninja setuptools
  RUN pip install --no-build-isolation git+https://github.com/Lightricks/LTX-Video-Q8-Kernels.git

  
  # Add extra config
  ADD src/extra_model_paths.yaml ./
  
  WORKDIR /
  
  # Add scripts
  ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
  RUN chmod +x /start.sh /restore_snapshot.sh
  
  # Add snapshot
  ADD snapshot.json /
  
  # Restore your custom nodes
  RUN /restore_snapshot.sh
  
  # Default entrypoint
  CMD ["/start.sh"]
  