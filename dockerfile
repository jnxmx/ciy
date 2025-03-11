# Define arguments
ARG DOCKER_FROM=runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

# Base NVidia CUDA Ubuntu image
FROM $DOCKER_FROM AS base

# Define additional arguments
ARG PYTORCH="2.6.0"
ARG CUDA="124"

# Set environment variables
ENV HF_HUB_ENABLE_HF_TRANSFER=1 \
    VIRTUAL_ENV="/workspace/ComfyUI/venv" \
    PATH="/workspace/ComfyUI/venv/bin:${PATH}"

# Install base dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        aria2 mc ffmpeg openssh-client \
        git-lfs vim zip unzip && \
    apt-get autoremove -y && \
    pip3 install --no-cache-dir --upgrade pip && \
    rm -rf /var/lib/apt/lists/*

# Install Filebrowser
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh -o get.sh && \
    chmod +x get.sh && ./get.sh && rm get.sh

# Create workspace and mount it
VOLUME ["/workspace"]

# Clone & setup ComfyUI
WORKDIR /workspace/ComfyUI
RUN if [ ! -d "/workspace/ComfyUI/.git" ]; then \
        git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI; \
    else \
        git -C /workspace/ComfyUI pull --rebase; \
    fi

# Set up virtual environment & install dependencies
RUN python -m venv /workspace/ComfyUI/venv && \
    /workspace/ComfyUI/venv/bin/python -m ensurepip --default-pip && \
    /workspace/ComfyUI/venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel && \
    /workspace/ComfyUI/venv/bin/pip install --no-cache-dir -U torch==$PYTORCH torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu$CUDA xformers && \
    /workspace/ComfyUI/venv/bin/pip install --no-cache-dir -r /workspace/ComfyUI/requirements.txt && \
    /workspace/ComfyUI/venv/bin/pip install --no-cache-dir \
        opencv-python imageio imageio-ffmpeg ffmpeg-python av runpod diffusers accelerate sageattention insightface face-alignment onnxruntime

# Clone & setup custom nodes dynamically
ENV CUSTOM_NODES="\
ltdrdata/ComfyUI-Manager \
jnxmx/ComfyUI_HuggingFace_Downloader \
kijai/ComfyUI-KJNodes \
Fannovel16/comfyui_controlnet_aux \
crystian/ComfyUI-Crystools \
Kosinkadink/ComfyUI-VideoHelperSuite \
willmiao/ComfyUI-Lora-Manager \
city96/ComfyUI-GGUF "
WORKDIR /workspace/ComfyUI/custom_nodes
RUN for repo in $CUSTOM_NODES; do \
        repo_url="https://github.com/$repo.git"; \
        repo_name=$(basename -s .git "$repo"); \
        if [ -d "$repo_name/.git" ]; then \
            git -C "$repo_name" pull --rebase; \
        else \
            git clone "$repo_url" "$repo_name"; \
        fi; \
    done && \
    for dir in /workspace/ComfyUI/custom_nodes/*; do \
        if [ -f "$dir/requirements.txt" ]; then \
            /workspace/ComfyUI/venv/bin/pip install --no-cache-dir -r "$dir/requirements.txt"; \
        fi; \
    done

# Install SageAttention
WORKDIR /workspace/
RUN git clone https://github.com/thu-ml/SageAttention.git

# Validate Nginx config before using it
COPY nginx.conf /etc/nginx/nginx.conf
COPY config.ini /workspace/ComfyUI/user/default/ComfyUI-Manager/config.ini

# Copy start script & fix line endings
COPY start.sh /start.sh
RUN sed -i 's/\r$//' /start.sh && chmod +x /start.sh

# Set working directory
WORKDIR /workspace/ComfyUI

# Set entrypoint
CMD ["bash", "/start.sh"]
