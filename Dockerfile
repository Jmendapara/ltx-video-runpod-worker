# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments for this stage with sensible defaults for standalone builds
ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL
ARG PYTORCH_VERSION

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install uv (latest) using official installer and create isolated venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment for all subsequent commands
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli + dependencies needed by it to install ComfyUI
RUN uv pip install comfy-cli pip setuptools wheel

# Install ComfyUI, then pin PyTorch to the correct CUDA version in the same
# layer so the cu128 wheels comfy-cli pulls don't bloat the image.
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi && \
    if [ "$ENABLE_PYTORCH_UPGRADE" = "true" ] && [ -n "${PYTORCH_VERSION}" ]; then \
      uv pip install --force-reinstall torch==${PYTORCH_VERSION} torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    elif [ "$ENABLE_PYTORCH_UPGRADE" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    fi && \
    rm -rf /root/.cache/pip /root/.cache/uv /root/.cache/comfy-cli /tmp/* && \
    uv cache clean

# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client

# Add application code and scripts
ADD src/start.sh src/network_volume.py handler.py test_input.json ./
RUN chmod +x /start.sh

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Model-specific custom nodes are installed in the final stage per MODEL_TYPE
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Set the default command to run when starting the container
CMD ["/start.sh"]

# Stage 2: Final image — download models directly (avoids COPY duplication
# that doubles disk usage during build for large models like INT8 ~83 GB).
FROM base AS final

ARG HUGGINGFACE_ACCESS_TOKEN
ARG MODEL_TYPE=ltx-2.3

WORKDIR /comfyui

RUN mkdir -p models/checkpoints models/vae models/unet models/clip models/text_encoders models/diffusion_models models/model_patches models/loras models/latent_upscale_models

# ---- Model-specific custom nodes and models ----
# Copy patch script once (used only for Hunyuan)
COPY scripts/patch-hunyuan-paths.py /tmp/patch-hunyuan-paths.py

# HunyuanImage: install nodes + patch paths, then download model
RUN if [ "$MODEL_TYPE" = "hunyuan-instruct-nf4" ] || [ "$MODEL_TYPE" = "hunyuan-instruct-int8" ]; then \
      comfy-node-install https://github.com/EricRollei/Comfy_HunyuanImage3 && \
      uv pip install "diffusers>=0.31.0" "transformers>=4.47.0,<5.0.0" "bitsandbytes>=0.48.2" "accelerate>=1.2.1" && \
      python3 /tmp/patch-hunyuan-paths.py; \
    fi
RUN rm -f /tmp/patch-hunyuan-paths.py

# LTX-2.3: install ComfyUI-LTXVideo, download checkpoint + text encoder + LoRA + spatial upscaler
RUN if [ "$MODEL_TYPE" = "ltx-2.3" ]; then \
      comfy-node-install https://github.com/Lightricks/ComfyUI-LTXVideo && \
      uv pip install "huggingface_hub[hf_xet]" && \
      HF_TOKEN="${HUGGINGFACE_ACCESS_TOKEN}" python3 -c "\
import os; from huggingface_hub import hf_hub_download; \
token = os.environ.get('HF_TOKEN') or None; \
hf_hub_download(repo_id='Lightricks/LTX-2.3', filename='ltx-2.3-22b-distilled.safetensors', local_dir='/comfyui/models/checkpoints', token=token); \
hf_hub_download(repo_id='Lightricks/LTX-2.3', filename='ltx-2.3-22b-distilled-lora-384.safetensors', local_dir='/comfyui/models/loras', token=token); \
hf_hub_download(repo_id='Lightricks/LTX-2.3', filename='ltx-2.3-spatial-upscaler-x2-1.0.safetensors', local_dir='/comfyui/models/latent_upscale_models', token=token); \
hf_hub_download(repo_id='Comfy-Org/ltx-2', filename='split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors', local_dir='/tmp/ltx-text-enc', token=token); \
import shutil; shutil.move('/tmp/ltx-text-enc/split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors', '/comfyui/models/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors'); \
" && \
      rm -rf /root/.cache/huggingface /tmp/hf_xet* /tmp/tmp* /tmp/ltx-text-enc && uv cache clean; \
    fi

RUN if [ "$MODEL_TYPE" = "sdxl" ]; then \
      wget -q -O models/checkpoints/sd_xl_base_1.0.safetensors https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors && \
      wget -q -O models/vae/sdxl_vae.safetensors https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors && \
      wget -q -O models/vae/sdxl-vae-fp16-fix.safetensors https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "sd3" ]; then \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/checkpoints/sd3_medium_incl_clips_t5xxlfp8.safetensors https://huggingface.co/stabilityai/stable-diffusion-3-medium/resolve/main/sd3_medium_incl_clips_t5xxlfp8.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "flux1-schnell" ]; then \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/unet/flux1-schnell.safetensors https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors && \
      wget -q -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
      wget -q -O models/clip/t5xxl_fp8_e4m3fn.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "flux1-dev" ]; then \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/unet/flux1-dev.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors && \
      wget -q -O models/clip/clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors && \
      wget -q -O models/clip/t5xxl_fp8_e4m3fn.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors && \
      wget -q --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/vae/ae.safetensors https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "flux1-dev-fp8" ]; then \
      wget -q -O models/checkpoints/flux1-dev-fp8.safetensors https://huggingface.co/Comfy-Org/flux1-dev/resolve/main/flux1-dev-fp8.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "z-image-turbo" ]; then \
      wget -q -O models/text_encoders/qwen_3_4b.safetensors https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors && \
      wget -q -O models/diffusion_models/z_image_turbo_bf16.safetensors https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors && \
      wget -q -O models/vae/ae.safetensors https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors && \
      wget -q -O models/model_patches/Z-Image-Turbo-Fun-Controlnet-Union.safetensors https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union.safetensors; \
    fi

RUN if [ "$MODEL_TYPE" = "hunyuan-instruct-nf4" ]; then \
      uv pip install "huggingface_hub[hf_xet]" && \
      python3 -c "from huggingface_hub import snapshot_download; snapshot_download('EricRollei/HunyuanImage-3.0-Instruct-Distil-NF4-v2', local_dir='/comfyui/models/HunyuanImage-3.0-Instruct-Distil-NF4')" && \
      rm -rf /root/.cache/huggingface /tmp/hf_xet* /tmp/tmp* && \
      uv cache clean; \
    fi

RUN if [ "$MODEL_TYPE" = "hunyuan-instruct-int8" ]; then \
      uv pip install "huggingface_hub[hf_xet]" && \
      python3 -c "from huggingface_hub import snapshot_download; snapshot_download('EricRollei/HunyuanImage-3.0-Instruct-Distil-INT8-v2', local_dir='/comfyui/models/HunyuanImage-3.0-Instruct-Distil-INT8')" && \
      rm -rf /root/.cache/huggingface /tmp/hf_xet* /tmp/tmp* && \
      uv cache clean; \
    fi

RUN if [ -d /comfyui/models/HunyuanImage-3.0-Instruct-Distil-NF4 ]; then \
      ln -s HunyuanImage-3.0-Instruct-Distil-NF4 /comfyui/models/HunyuanImage-3.0-Instruct-Distil-NF4-v2; \
    fi && \
    if [ -d /comfyui/models/HunyuanImage-3.0-Instruct-Distil-INT8 ]; then \
      ln -s HunyuanImage-3.0-Instruct-Distil-INT8 /comfyui/models/HunyuanImage-3.0-Instruct-Distil-INT8-v2; \
    fi
