variable "DOCKERHUB_REPO" {
  default = "runpod"
}

variable "DOCKERHUB_IMG" {
  default = "worker-comfyui"
}

variable "RELEASE_VERSION" {
  default = "latest"
}

variable "COMFYUI_VERSION" {
  default = "latest"
}

# Global defaults for standard CUDA 12.6.3 images
variable "BASE_IMAGE" {
  default = "nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04"
}

variable "CUDA_VERSION_FOR_COMFY" {
  default = "12.6"
}

variable "ENABLE_PYTORCH_UPGRADE" {
  default = "true"
}

variable "PYTORCH_INDEX_URL" {
  default = "https://download.pytorch.org/whl/cu126"
}

variable "HUGGINGFACE_ACCESS_TOKEN" {
  default = ""
}

variable "LTX_VARIANT" {
  default = "distilled"
}

group "default" {
  targets = ["base", "sdxl", "sd3", "flux1-schnell", "flux1-dev", "flux1-dev-fp8", "z-image-turbo", "ltx-2.3", "ltx-2.3-dev", "base-cuda12-8-1"]
}

target "base" {
  context = "."
  dockerfile = "Dockerfile"
  target = "base"
  platforms = ["linux/amd64"]
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    MODEL_TYPE = "base"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-base"]
}

target "sdxl" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    MODEL_TYPE = "sdxl"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-sdxl"]
  inherits = ["base"]
}

target "sd3" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    MODEL_TYPE = "sd3"
    HUGGINGFACE_ACCESS_TOKEN = "${HUGGINGFACE_ACCESS_TOKEN}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-sd3"]
  inherits = ["base"]
}

target "flux1-schnell" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    MODEL_TYPE = "flux1-schnell"
    HUGGINGFACE_ACCESS_TOKEN = "${HUGGINGFACE_ACCESS_TOKEN}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-flux1-schnell"]
  inherits = ["base"]
}

target "flux1-dev" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    MODEL_TYPE = "flux1-dev"
    HUGGINGFACE_ACCESS_TOKEN = "${HUGGINGFACE_ACCESS_TOKEN}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-flux1-dev"]
  inherits = ["base"]
}

target "flux1-dev-fp8" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    MODEL_TYPE = "flux1-dev-fp8"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-flux1-dev-fp8"]
  inherits = ["base"]
}

target "z-image-turbo" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    MODEL_TYPE = "z-image-turbo"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-z-image-turbo"]
  inherits = ["base"]
}

target "ltx-2.3" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    MODEL_TYPE = "ltx-2.3"
    LTX_VARIANT = "distilled"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-ltx-2.3"]
  inherits = ["base"]
}

target "ltx-2.3-dev" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    MODEL_TYPE = "ltx-2.3"
    LTX_VARIANT = "dev"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-ltx-2.3-dev"]
  inherits = ["base"]
}

target "hunyuan-instruct-nf4" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    MODEL_TYPE = "hunyuan-instruct-nf4"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-hunyuan-instruct-nf4"]
  inherits = ["base"]
}

target "hunyuan-instruct-int8" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL = "${PYTORCH_INDEX_URL}"
    MODEL_TYPE = "hunyuan-instruct-int8"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-hunyuan-instruct-int8"]
  inherits = ["base"]
}

target "ltx-2.3-blackwell" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = ""
    ENABLE_PYTORCH_UPGRADE = "true"
    PYTORCH_INDEX_URL = "https://download.pytorch.org/whl/cu128"
    MODEL_TYPE = "ltx-2.3"
    LTX_VARIANT = "distilled"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-ltx-2.3-blackwell"]
  platforms = ["linux/amd64"]
}

target "ltx-2.3-dev-blackwell" {
  context = "."
  dockerfile = "Dockerfile"
  target = "final"
  args = {
    BASE_IMAGE = "nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = ""
    ENABLE_PYTORCH_UPGRADE = "true"
    PYTORCH_INDEX_URL = "https://download.pytorch.org/whl/cu128"
    MODEL_TYPE = "ltx-2.3"
    LTX_VARIANT = "dev"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-ltx-2.3-dev-blackwell"]
  platforms = ["linux/amd64"]
}

target "base-cuda12-8-1" {
  context = "."
  dockerfile = "Dockerfile"
  target = "base"
  platforms = ["linux/amd64"]
  args = {
    BASE_IMAGE = "nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
    COMFYUI_VERSION = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY = ""
    ENABLE_PYTORCH_UPGRADE = "true"
    PYTORCH_INDEX_URL = "https://download.pytorch.org/whl/cu128"
    MODEL_TYPE = "base"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-base-cuda12.8.1"]
}

