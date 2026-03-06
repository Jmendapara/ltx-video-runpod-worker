#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Setup ComfyUI + LTX-2.3 on a RunPod GPU Pod
#
# Usage:
#   1. Create a RunPod GPU Pod (A100 40GB/80GB or 32GB+ VRAM, 100GB+ disk)
#   2. Open the web terminal or SSH in
#   3. Run:
#        curl -fsSL https://raw.githubusercontent.com/Jmendapara/ltx-video-runpod-worker/main/scripts/setup-pod.sh | bash
#
# The script installs ComfyUI, ComfyUI-LTXVideo nodes, downloads the
# LTX-2.3 22B distilled checkpoint, and starts ComfyUI on port 8188.
#
# For gated model access, set HF_TOKEN before running:
#        export HF_TOKEN="hf_xxxx"
#        curl -fsSL ... | bash
# =============================================================================

WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_DIR="${WORKSPACE}/ComfyUI"
CHECKPOINT_NAME="ltx-2.3-22b-distilled.safetensors"
HF_REPO="Lightricks/LTX-2.3"
MODEL_SIZE="~46 GB"

echo "============================================="
echo " ComfyUI + LTX-2.3 Pod Setup"
echo "============================================="
echo "  HF repo:     ${HF_REPO}"
echo "  Checkpoint:  ${CHECKPOINT_NAME}"
echo "  Model size:  ${MODEL_SIZE}"
echo "  Workspace:   ${WORKSPACE}"
echo "  ComfyUI:     ${COMFYUI_DIR}"
echo "============================================="

# ---- Step 1: Install ComfyUI ----
if [ -f "${COMFYUI_DIR}/main.py" ]; then
    echo "[1/5] ComfyUI already installed at ${COMFYUI_DIR}"
else
    echo "[1/5] Installing ComfyUI..."
    pip install comfy-cli
    /usr/bin/yes | comfy --workspace "${COMFYUI_DIR}" install --nvidia
    echo "[1/5] ComfyUI installed."
fi

if [ -x "${COMFYUI_DIR}/.venv/bin/pip" ]; then
    PIP="${COMFYUI_DIR}/.venv/bin/pip"
    PYTHON="${COMFYUI_DIR}/.venv/bin/python"
else
    PIP="pip"
    PYTHON="python3"
fi

# ---- Step 2: Install ComfyUI-LTXVideo custom nodes ----
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes/ComfyUI-LTXVideo"
if [ -d "${CUSTOM_NODES_DIR}" ]; then
    echo "[2/5] ComfyUI-LTXVideo already cloned, pulling latest..."
    (cd "${CUSTOM_NODES_DIR}" && git pull)
else
    echo "[2/5] Cloning ComfyUI-LTXVideo..."
    git clone https://github.com/Lightricks/ComfyUI-LTXVideo "${CUSTOM_NODES_DIR}"
fi

echo "[2/5] Installing node requirements..."
$PIP install -r "${CUSTOM_NODES_DIR}/requirements.txt"
$PIP install "huggingface_hub[hf_xet]"

# ---- Step 3: Download LTX-2.3 checkpoint ----
CHECKPOINT_DIR="${COMFYUI_DIR}/models/checkpoints"
mkdir -p "${CHECKPOINT_DIR}"
CHECKPOINT_PATH="${CHECKPOINT_DIR}/${CHECKPOINT_NAME}"

if [ -f "${CHECKPOINT_PATH}" ]; then
    echo "[3/5] Checkpoint already present: ${CHECKPOINT_PATH}"
else
    echo "[3/5] Downloading ${HF_REPO} ${CHECKPOINT_NAME} (${MODEL_SIZE})..."
    echo "       Accept the model license at https://huggingface.co/${HF_REPO} if gated."
    export HF_TOKEN="${HF_TOKEN:-}"
    $PYTHON -c "
from huggingface_hub import hf_hub_download
import os
token = os.environ.get('HF_TOKEN') or os.environ.get('HUGGINGFACE_ACCESS_TOKEN')
hf_hub_download(
    repo_id='${HF_REPO}',
    filename='${CHECKPOINT_NAME}',
    local_dir='${CHECKPOINT_DIR}',
    token=token,
)
"
    echo "[3/5] Checkpoint downloaded."
fi

# ---- Step 4: Versions ----
echo ""
echo "============================================="
echo " Setup Complete — Versions"
echo "============================================="
$PYTHON -c "
import sys
print(f'  Python: {sys.executable}')
try:
    import torch
    print(f'  PyTorch: {torch.__version__}')
    print(f'  CUDA: {torch.cuda.is_available()}')
    if torch.cuda.is_available():
        print(f'  GPU: {torch.cuda.get_device_name(0)}')
except Exception as e:
    print(f'  (torch: {e})')
"
echo "============================================="
echo ""
echo " Starting ComfyUI on port 8188..."
echo " Open the RunPod Connect → HTTP 8188 link."
echo ""
echo " URL: https://<POD_ID>-8188.proxy.runpod.net/"
echo "============================================="

cd "${COMFYUI_DIR}"
pkill -f "main.py" 2>/dev/null; sleep 2
$PYTHON main.py --listen 0.0.0.0 --port 8188
