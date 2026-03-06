#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Build Docker image on a RunPod GPU Pod and push to Docker Hub.
#
# Usage (run inside a RunPod pod via SSH or web terminal):
#
#   export DOCKERHUB_USERNAME="your-dockerhub-user"
#   export DOCKERHUB_TOKEN="your-dockerhub-access-token"
#   export IMAGE_TAG="your-user/worker-comfyui:latest-ltx-2.3"
#   export MODEL_TYPE="ltx-2.3"
#   bash build-on-pod.sh
#
# Prerequisites:
#   - A RunPod GPU pod with Docker (or Docker-in-Docker).
#   - At least 120 GB disk for ltx-2.3, 80 GB for base.
# =============================================================================

REPO_URL="${REPO_URL:-https://github.com/Jmendapara/ltx-video-runpod-worker.git}"
BRANCH="${BRANCH:-main}"
MODEL_TYPE="${MODEL_TYPE:-ltx-2.3}"
COMFYUI_VERSION="${COMFYUI_VERSION:-v0.14.2}"
HUGGINGFACE_ACCESS_TOKEN="${HUGGINGFACE_ACCESS_TOKEN:-}"

# Docker Hub credentials
: "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME}"
: "${DOCKERHUB_TOKEN:?Set DOCKERHUB_TOKEN}"
: "${IMAGE_TAG:?Set IMAGE_TAG (e.g. yourdockerhubuser/worker-comfyui:latest-ltx-2.3)}"

echo "============================================="
echo " RunPod Docker Image Builder"
echo "============================================="
echo "  Repo:          ${REPO_URL}"
echo "  Branch:        ${BRANCH}"
echo "  Model type:    ${MODEL_TYPE}"
echo "  ComfyUI ver:   ${COMFYUI_VERSION}"
echo "  Image tag:     ${IMAGE_TAG}"
echo "  CUDA level:   ${CUDA_LEVEL:-12.6}"
echo "  HF token:      ${HUGGINGFACE_ACCESS_TOKEN:+(set)}"
echo "============================================="

# ---- Step 1: Ensure Docker (with BuildKit/buildx) is installed and running ----
if ! command -v docker &>/dev/null || ! docker buildx version &>/dev/null 2>&1; then
    echo "[1/5] Installing Docker via get.docker.com..."
    curl -fsSL https://get.docker.com | sh
    echo "[1/5] Docker installed."
else
    echo "[1/5] Docker already available: $(docker --version)"
fi

if ! docker info &>/dev/null 2>&1; then
    echo "[1/5] Starting Docker daemon..."
    if ! systemctl start docker 2>/dev/null; then
        dockerd &>/dev/null &
        sleep 5
    fi
fi
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon is not running."; exit 1; }

# ---- Step 2: Log into Docker Hub ----
echo "[2/5] Logging into Docker Hub..."
echo "${DOCKERHUB_TOKEN}" | docker login --username "${DOCKERHUB_USERNAME}" --password-stdin
echo "[2/5] Logged in."

# ---- Step 3: Clone the repo ----
WORK_DIR="/tmp/build-workspace"
if [ -d "${WORK_DIR}" ]; then
    echo "[3/5] Cleaning previous build workspace..."
    rm -rf "${WORK_DIR}"
fi
echo "[3/5] Cloning repo (branch: ${BRANCH})..."
git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${WORK_DIR}"
cd "${WORK_DIR}"
echo "[3/5] Repo cloned."

# ---- Step 4: Build the Docker image ----
echo "[4/5] Building Docker image (this will take a while)..."
echo "       MODEL_TYPE=${MODEL_TYPE}, target=final"

BUILD_ARGS=(
    --platform linux/amd64
    --target final
    --no-cache
    --build-arg "MODEL_TYPE=${MODEL_TYPE}"
    --build-arg "COMFYUI_VERSION=${COMFYUI_VERSION}"
)

# CUDA version selection.
# Default: CUDA 12.6 (works with A100, H100, driver >= 560.x).
# Override: set CUDA_LEVEL=12.8 for Blackwell GPUs (RTX PRO 6000, sm_120, driver >= 570.x).
CUDA_LEVEL="${CUDA_LEVEL:-12.6}"
PYTORCH_VERSION="${PYTORCH_VERSION:-}"

if [ "${CUDA_LEVEL}" = "12.8" ]; then
    BUILD_ARGS+=(
        --build-arg "BASE_IMAGE=nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
        --build-arg "ENABLE_PYTORCH_UPGRADE=true"
        --build-arg "PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu128"
        --build-arg "PYTORCH_VERSION=${PYTORCH_VERSION}"
    )
    echo "       Using CUDA 12.8 base + PyTorch ${PYTORCH_VERSION:-latest}+cu128 (Blackwell, needs driver >= 570)"
else
    BUILD_ARGS+=(
        --build-arg "BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04"
        --build-arg "CUDA_VERSION_FOR_COMFY=12.6"
        --build-arg "ENABLE_PYTORCH_UPGRADE=true"
        --build-arg "PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu126"
        --build-arg "PYTORCH_VERSION=${PYTORCH_VERSION}"
    )
    echo "       Using CUDA 12.6 base + PyTorch ${PYTORCH_VERSION:-latest}+cu126 (default, works with driver >= 560)"
fi

if [ -n "${HUGGINGFACE_ACCESS_TOKEN}" ]; then
    BUILD_ARGS+=(--build-arg "HUGGINGFACE_ACCESS_TOKEN=${HUGGINGFACE_ACCESS_TOKEN}")
fi

# Free disk: remove old images, containers, and build cache before building
docker system prune -af --volumes 2>/dev/null || true
docker builder prune -af 2>/dev/null || true
echo "       Available disk: $(df -h /var/lib/docker 2>/dev/null | tail -1 | awk '{print $4}') free"

# INT8 images (~83GB) need the docker-container buildx driver to avoid
# the "Lchown ... no such file or directory" overlayfs bug.
# NF4 and smaller images use the default driver (faster, no OCI export overhead).
if [ "${MODEL_TYPE}" = "hunyuan-instruct-int8" ]; then
    BUILDER_NAME="large-image-builder"
    if ! docker buildx inspect "${BUILDER_NAME}" &>/dev/null; then
        echo "       Creating buildx builder '${BUILDER_NAME}' (docker-container driver)..."
        docker buildx create --name "${BUILDER_NAME}" --driver docker-container --use
    else
        docker buildx use "${BUILDER_NAME}"
    fi
    echo "       Using docker-container builder (required for INT8 large layers)"
    docker buildx build "${BUILD_ARGS[@]}" --load -t "${IMAGE_TAG}" .
else
    docker buildx use default 2>/dev/null || true
    echo "       Using default docker builder"
    docker buildx build "${BUILD_ARGS[@]}" -t "${IMAGE_TAG}" .
fi

echo "[4/5] Build complete!"
echo "       Image size: $(docker images "${IMAGE_TAG}" --format '{{.Size}}')"

# ---- Step 5: Push to Docker Hub ----
echo "[5/5] Pushing ${IMAGE_TAG} to Docker Hub..."
docker push "${IMAGE_TAG}"
echo "[5/5] Push complete!"

echo ""
echo "============================================="
echo " SUCCESS"
echo "============================================="
echo " Image pushed: ${IMAGE_TAG}"
echo ""
echo " Next steps:"
echo "   1. Go to https://www.runpod.io/console/serverless"
echo "   2. Create a new endpoint with container image:"
echo "      ${IMAGE_TAG}"
if [ "${CUDA_LEVEL}" = "12.8" ]; then
echo "   3. Pick GPU: RTX PRO 6000 Blackwell 96GB (built with CUDA 12.8)"
else
echo "   3. Pick GPU: A100 40GB/80GB or H100 (built with CUDA 12.6)"
fi
echo "   4. Set Min Workers=0, Max Workers=1"
echo "   5. Destroy this build server to stop charges!"
echo "============================================="
