# LTX-2.3 — Serverless ComfyUI Worker

> [ComfyUI](https://github.com/comfyanonymous/ComfyUI) + [LTX-2.3](https://huggingface.co/Lightricks/LTX-2.3) (22B distilled) as a serverless API on [RunPod](https://www.runpod.io/)

---

## Table of Contents

- [Overview](#overview)
- [Model](#model)
- [Step 1: Build the Docker Image](#step-1-build-the-docker-image)
- [Step 2: Push to a Container Registry](#step-2-push-to-a-container-registry)
- [Step 3: Deploy on RunPod](#step-3-deploy-on-runpod)
- [Step 4: Test Your Endpoint](#step-4-test-your-endpoint)
- [API Specification](#api-specification)
- [Environment Variables](#environment-variables)
- [Troubleshooting](#troubleshooting)

---

## Overview

This project packages ComfyUI with the **LTX-2.3 22B distilled** video model ([Lightricks/LTX-2.3](https://huggingface.co/Lightricks/LTX-2.3)) baked into a Docker image. It runs as a serverless worker on RunPod — you send a workflow via API and receive generated videos (or images) as base64 or S3 URLs.

The model is baked directly into the Docker image. No network volume is required.

**ComfyUI custom nodes:** [ComfyUI-LTXVideo](https://github.com/Lightricks/ComfyUI-LTXVideo) (Lightricks).

---

## Model

| Property | Value |
|----------|--------|
| **Model** | [LTX-2.3 22B distilled](https://huggingface.co/Lightricks/LTX-2.3) |
| **Checkpoint** | `ltx-2.3-22b-distilled.safetensors` |
| **On-disk size** | ~46 GB |
| **Docker image size** | ~55–60 GB (estimated) |
| **VRAM** | 32 GB+ recommended |
| **GPU** | A100 40GB / A100 80GB / similar |
| **Capabilities** | Text-to-video, image-to-video, video-to-video (via ComfyUI-LTXVideo nodes) |

You must accept the [model license](https://huggingface.co/Lightricks/LTX-2.3) on Hugging Face. For gated access, set `HUGGINGFACE_ACCESS_TOKEN` (or `HF_TOKEN`) when building or running.

---

## Step 1: Build the Docker Image

Build on a machine with enough disk (e.g. 120 GB+ free). A GPU is not required for building.

### 1.1 Set environment variables

```bash
export DOCKERHUB_USERNAME="your-dockerhub-username"
export DOCKERHUB_TOKEN="dckr_pat_your_access_token"
export IMAGE_TAG="your-dockerhub-username/worker-comfyui:latest-ltx-2.3"
export MODEL_TYPE="ltx-2.3"
```

If the model is gated, set a Hugging Face token:

```bash
export HUGGINGFACE_ACCESS_TOKEN="hf_xxxxxxxx"
```

### 1.2 Build

From this repo:

```bash
docker buildx build \
  --platform linux/amd64 \
  --target final \
  --build-arg MODEL_TYPE=ltx-2.3 \
  -t "${IMAGE_TAG}" \
  .
```

Or use the remote build script (from an empty directory like `/tmp`):

```bash
cd /tmp
curl -fsSL "https://raw.githubusercontent.com/Jmendapara/ltx-video-runpod-worker/main/scripts/build-on-pod.sh?ts=$(date +%s)" | bash
```

Build time is typically **60–90 minutes** (model download ~46 GB plus image build).

---

## Step 2: Push to a Container Registry

```bash
docker push your-dockerhub-username/worker-comfyui:latest-ltx-2.3
```

For large images, [GitHub Container Registry (GHCR)](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) often handles big layers better than Docker Hub.

---

## Step 3: Deploy on RunPod

1. Create a [RunPod](https://www.runpod.io/) account and add credits.
2. Get an API key: [Settings → API Keys](https://www.runpod.io/console/serverless/user/settings).
3. [Create a Serverless Endpoint](https://www.runpod.io/console/serverless):
   - **Container image:** `your-dockerhub-username/worker-comfyui:latest-ltx-2.3`
   - **GPU:** A100 40GB or A100 80GB (or 32 GB+ VRAM).
   - **Container disk:** 80 GB or more.
   - **Min workers:** 0 (scale to zero).
   - **Max workers:** 1 or more as needed.
4. Do not set a custom start command; the image uses its built-in `/start.sh`.
5. Do not attach a network volume unless you need extra models.
6. Note the **Endpoint ID** for API calls.

---

## Step 4: Test Your Endpoint

Use the RunPod [runsync](https://docs.runpod.io/serverless/references/runsync) or [run](https://docs.runpod.io/serverless/references/run) API. Your `input` must include a ComfyUI workflow that uses the **LTXVideo** nodes and the checkpoint `ltx-2.3-22b-distilled.safetensors`.

Example (replace `YOUR_ENDPOINT_ID` and `YOUR_RUNPOD_API_KEY`):

```bash
curl -X POST "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/runsync" \
  -H "Authorization: Bearer YOUR_RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "workflow": { }
    }
  }'
```

Build the workflow in ComfyUI with ComfyUI-LTXVideo installed, then use **Workflow → Export (API)** and paste the result into `input.workflow`. See [ComfyUI-LTXVideo](https://github.com/Lightricks/ComfyUI-LTXVideo) and [LTX docs](https://docs.ltx.video/) for node usage.

---

## API Specification

Same as the generic ComfyUI RunPod worker:

- **Input:** `input.workflow` (ComfyUI API format), optional `input.images` for base64 inputs.
- **Output:** `output.images` (base64 or S3 URLs if configured).

See [RunPod serverless docs](https://docs.runpod.io/serverless) for request/response details.

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `BUCKET_ENDPOINT_URL` | No | S3 endpoint for uploading outputs |
| `BUCKET_ACCESS_KEY_ID` | No | S3 access key |
| `BUCKET_SECRET_ACCESS_KEY` | No | S3 secret key |
| `COMFY_ORG_API_KEY` | No | Comfy.org API key for API nodes |
| `COMFY_LOG_LEVEL` | No | `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `REFRESH_WORKER` | No | `true` to restart worker after each job |

---

## Troubleshooting

- **Cold start:** First request after scale-to-zero pulls the image (~55–60 GB) and loads the model; allow several minutes.
- **OOM:** Use a GPU with at least 32 GB VRAM (e.g. A100 40GB/80GB).
- **Gated model:** Accept the [LTX-2.3 license](https://huggingface.co/Lightricks/LTX-2.3) and pass `HUGGINGFACE_ACCESS_TOKEN` (or `HF_TOKEN`) at build time if the download fails.

---

## Other Docker Targets

This repo supports multiple ComfyUI model types. Build with `MODEL_TYPE` (or the corresponding docker-bake target):

| MODEL_TYPE | Description |
|------------|-------------|
| `base` | ComfyUI only, no models |
| `sdxl` | Stable Diffusion XL |
| `sd3` | Stable Diffusion 3 |
| `flux1-schnell` | FLUX.1 schnell |
| `flux1-dev` | FLUX.1 dev |
| `z-image-turbo` | Z-Image Turbo |
| **`ltx-2.3`** | **LTX-2.3 22B distilled (this worker)** |
| `hunyuan-instruct-nf4` | HunyuanImage 3.0 Instruct NF4 |
| `hunyuan-instruct-int8` | HunyuanImage 3.0 Instruct INT8 |

Example:

```bash
docker buildx build --build-arg MODEL_TYPE=ltx-2.3 --target final -t myuser/worker-comfyui:ltx-2.3 .
```
