# LTX-2.3 — Serverless ComfyUI Video Worker

> ComfyUI + LTX-2.3 22B Distilled as a serverless video generation API on RunPod

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
- [Cost Estimates](#cost-estimates)
- [Troubleshooting](#troubleshooting)

---

## Overview

This project packages ComfyUI with the **LTX-2.3 22B distilled** video model baked into a Docker image. The image runs as a serverless worker on RunPod — you send a workflow via API and receive generated videos back as base64 strings or S3 URLs.

The model is baked directly into the Docker image. No network volume is required.

**Key features:**
- **Text-to-video** with audio generation (LTX-2.3 supports joint audio-video)
- **2x spatial upscaling** via latent upsampler (distilled LoRA pass)
- **24 FPS** output with configurable frame counts (default 121 frames = ~5 seconds)
- **No prompt enhancement** — direct prompt-to-video pipeline

**ComfyUI custom nodes:** [ComfyUI-LTXVideo](https://github.com/Lightricks/ComfyUI-LTXVideo) (Lightricks)

---

## Model

| Property | Value |
|----------|-------|
| **Model** | [LTX-2.3 22B distilled](https://huggingface.co/Lightricks/LTX-2.3) |
| **Architecture** | Diffusion Transformer (22B parameters) |
| **Checkpoint** | `ltx-2.3-22b-distilled.safetensors` (~46 GB) |
| **Text Encoder** | `gemma_3_12B_it_fp4_mixed.safetensors` (~6 GB) |
| **Distilled LoRA** | `ltx-2.3-22b-distilled-lora-384.safetensors` |
| **Spatial Upscaler** | `ltx-2.3-spatial-upscaler-x2-1.0.safetensors` |
| **Total on-disk** | ~55 GB |
| **Docker image size** | ~65–75 GB (estimated) |
| **VRAM required** | 32 GB+ (40 GB+ recommended for upscaled output) |
| **Recommended GPU** | **RTX PRO 6000 Blackwell 96GB** (requires CUDA 12.8 build) |
| **Also works on** | A100 40GB / A100 80GB / H100 (CUDA 12.6 build) |
| **Capabilities** | Text-to-video, audio generation, 2x spatial upscaling |
| **Default output** | 640×480 → upscaled to 1280×960, 121 frames @ 24 FPS (~5 sec) |

### Model Storage Layout

```
ComfyUI/models/
├── checkpoints/
│   └── ltx-2.3-22b-distilled.safetensors       (~46 GB)
├── text_encoders/
│   └── gemma_3_12B_it_fp4_mixed.safetensors     (~6 GB)
├── loras/
│   └── ltx-2.3-22b-distilled-lora-384.safetensors
└── latent_upscale_models/
    └── ltx-2.3-spatial-upscaler-x2-1.0.safetensors
```

---

## Step 1: Build the Docker Image

The image must be built on a remote server with enough disk space. A GPU is **not** needed for building.

### 1.1 Create a Cloud Server

Use a cheap VPS from Hetzner Cloud or any provider.

| Setting | Value |
|---------|-------|
| Provider | Hetzner Cloud (or any VPS) |
| OS | Ubuntu 24.04 |
| Server type | CPX51 (8 vCPU, 16 GB RAM, 240 GB disk) or larger |
| Disk | 250 GB minimum |
| Estimated cost | ~$0.04/hour |

> **Important:** Docker needs space for intermediate build layers in addition to the final image. The image is ~65–75 GB. Models are downloaded directly in the final stage (no multi-stage COPY) to avoid doubling disk usage, but build layers still need headroom.

### 1.2 Add an SSH Key (recommended)

Using an SSH key avoids Hetzner emailing you root credentials.

**Generate a key** (skip if you already have one at `~/.ssh/id_ed25519`):

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

Press Enter for the default file location and optionally set a passphrase.

**Add it to Hetzner:** Go to **Security > SSH Keys > Add SSH Key**, paste the contents of your public key:

```bash
# macOS / Linux
cat ~/.ssh/id_ed25519.pub

# Windows PowerShell
Get-Content ~\.ssh\id_ed25519.pub | Set-Clipboard
```

Select this key when creating the server.

### 1.3 SSH into the Server

```bash
ssh root@YOUR_SERVER_IP
```

> **"REMOTE HOST IDENTIFICATION HAS CHANGED"** — If you reuse an IP from a previous server, SSH will reject the connection because the old fingerprint is cached. Remove it and reconnect:
>
> ```bash
> ssh-keygen -R YOUR_SERVER_IP
> ssh root@YOUR_SERVER_IP
> ```

### 1.4 Install Docker

```bash
curl -fsSL https://get.docker.com | sh
systemctl start docker
```

### 1.5 Set Environment Variables

**For RTX PRO 6000 Blackwell 96GB (recommended):**

```bash
export DOCKERHUB_USERNAME="your-dockerhub-username"
export DOCKERHUB_TOKEN="dckr_pat_your_access_token"
export IMAGE_TAG="your-dockerhub-username/worker-comfyui:latest-ltx-2.3"
export MODEL_TYPE="ltx-2.3"
export CUDA_LEVEL=12.8
```

**For A100 / H100 (CUDA 12.6):**

```bash
export DOCKERHUB_USERNAME="your-dockerhub-username"
export DOCKERHUB_TOKEN="dckr_pat_your_access_token"
export IMAGE_TAG="your-dockerhub-username/worker-comfyui:latest-ltx-2.3"
export MODEL_TYPE="ltx-2.3"
# CUDA_LEVEL defaults to 12.6, no need to set it
```

If the model requires a Hugging Face token (gated access):

```bash
export HUGGINGFACE_ACCESS_TOKEN="hf_xxxxxxxx"
```

### 1.6 CUDA Level Selection

The `CUDA_LEVEL` variable controls which GPU architectures the image supports. **You must set this correctly for your target GPU.**

| CUDA_LEVEL | Base Image | PyTorch Wheels | Driver Needed | GPUs |
|------------|-----------|----------------|---------------|------|
| 12.6 (default) | cuda:12.6.3 | cu126 | >= 560.x | A100, H100, A6000, L40S |
| **12.8** | **cuda:12.8.1** | **cu128** | **>= 570.x** | **RTX PRO 6000 Blackwell 96GB** |

> **Important:** The RTX PRO 6000 is a Blackwell GPU (sm_120). If you build with CUDA 12.6, the model will fail at runtime with `CUDA error: no kernel image is available for execution on the device`. Always use `CUDA_LEVEL=12.8` for Blackwell GPUs.

### 1.7 Run the Build Script

```bash
cd /tmp && curl -fsSL "https://raw.githubusercontent.com/Jmendapara/ltx-video-runpod-worker/main/scripts/build-on-pod.sh?ts=$(date +%s)" | bash
```

> **Note:** Always run from `/tmp` (or any directory outside the build workspace). The script deletes and re-creates `/tmp/build-workspace`, which fails if your shell is currently inside that directory.
>
> The `?ts=$(date +%s)` query parameter busts GitHub's raw content CDN cache so you always get the latest version of the script.

This script:

1. Installs Docker if needed
2. Logs into Docker Hub
3. Clones this repo
4. Builds the Docker image with all LTX-2.3 models baked in
5. Pushes the image to Docker Hub

Expect **60–90 minutes** (mostly model download at ~55 GB plus image build). The Docker image export step alone can take 20–30 minutes due to the large image size.

### 1.8 Delete the Server

Once the push completes, **delete the server immediately** to stop charges.

---

## Step 2: Push to a Container Registry

The build script pushes to Docker Hub automatically. If the push fails (502 errors are common for large layers), retry:

```bash
docker push your-dockerhub-username/worker-comfyui:latest-ltx-2.3
```

Docker skips layers that already uploaded successfully and only retries the failed ones.

### Alternative: Push to GitHub Container Registry

GHCR handles large layers more reliably than Docker Hub:

```bash
echo YOUR_GITHUB_PAT | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
docker tag your-dockerhub-username/worker-comfyui:latest-ltx-2.3 \
  ghcr.io/YOUR_GITHUB_USERNAME/worker-comfyui:latest-ltx-2.3
docker push ghcr.io/YOUR_GITHUB_USERNAME/worker-comfyui:latest-ltx-2.3
```

RunPod accepts images from any public container registry — Docker Hub, GHCR, Amazon ECR, etc.

---

## Step 3: Deploy on RunPod

### 3.1 Create a RunPod Account

Sign up at [runpod.io](https://www.runpod.io/) and add credits.

### 3.2 Get a RunPod API Key

Go to Settings > API Keys and generate a key. Save it — you'll need it to call the endpoint.

### 3.3 Create a Serverless Endpoint

1. Go to [RunPod Serverless Console](https://www.runpod.io/console/serverless)
2. Click **+ New Endpoint**
3. Configure with these settings:

| Setting | Value | Notes |
|---------|-------|-------|
| **Container Image** | `your-dockerhub-username/worker-comfyui:latest-ltx-2.3` | Or `ghcr.io/...` if using GHCR |
| **GPU** | **RTX PRO 6000 Blackwell 96GB** | Requires CUDA 12.8 build. A100 80GB also works with CUDA 12.6 build |
| **Min Workers** | 0 | Scales to zero when idle (no cost) |
| **Max Workers** | 1 | Increase for higher throughput |
| **Container Disk** | 120 GB | Must be larger than the image (~75 GB) plus scratch space |
| **Idle Timeout** | 5 seconds | How long a warm worker waits before shutting down |
| **FlashBoot** | Enabled (if available) | Speeds up cold starts |

> **GPU Selection:** The RTX PRO 6000 Blackwell 96GB has 96 GB VRAM — far more than the ~35–40 GB this model requires. This gives ample headroom for higher resolutions, longer videos, and the 2x spatial upscale pass. Make sure you built the image with `CUDA_LEVEL=12.8`.

4. **Do NOT set** a start command — the image uses its built-in `/start.sh`
5. **Do NOT attach** a network volume — the model is baked into the image
6. Click **Create**
7. Note your **Endpoint ID** from the endpoint overview page

### 3.4 Environment Variables (Optional)

No environment variables are required for basic operation. The endpoint works out of the box.

If you need optional features, add these in the RunPod endpoint template under **Environment Variables**:

| Variable | Required | Description |
|----------|----------|-------------|
| BUCKET_ENDPOINT_URL | No | S3 bucket URL to upload videos instead of returning base64 |
| BUCKET_ACCESS_KEY_ID | No | AWS access key for S3 upload |
| BUCKET_SECRET_ACCESS_KEY | No | AWS secret key for S3 upload |
| COMFY_ORG_API_KEY | No | Comfy.org API key for API Nodes |
| COMFY_LOG_LEVEL | No | Logging verbosity: DEBUG, INFO, WARNING, ERROR (default: DEBUG) |
| REFRESH_WORKER | No | Set true to restart the worker after each job for a clean state |

> **Recommendation:** For video output, configure S3 upload (`BUCKET_ENDPOINT_URL`). Video files can be large (10–50+ MB) and may exceed RunPod's response size limits when returned as base64.

---

## Step 4: Test Your Endpoint

### 4.1 First Request (Cold Start)

The first request after the endpoint is created (or after it scales to zero) triggers a **cold start**:

- RunPod pulls the Docker image (first time only — cached after that)
- ComfyUI starts and loads the model into GPU VRAM

The first-ever cold start takes **15–30 minutes** (~75 GB image pull). Subsequent cold starts take **2–5 minutes** (model loading only, image is cached).

### 4.2 Text-to-Video Request

Send a workflow to the `/run` endpoint (async, recommended for video generation which takes 1–5 minutes):

```bash
curl -X POST "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/run" \
  -H "Authorization: Bearer YOUR_RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "workflow": {
        "75": {
          "inputs": {
            "filename_prefix": "video/LTX-2.3",
            "format": "auto",
            "codec": "auto",
            "video": ["153:133", 0]
          },
          "class_type": "SaveVideo",
          "_meta": { "title": "Save Video" }
        },
        "153:112": {
          "inputs": {
            "steps": 20, "max_shift": 2.05, "base_shift": 0.95,
            "stretch": true, "terminal": 0.1,
            "latent": ["153:122", 0]
          },
          "class_type": "LTXVScheduler"
        },
        "153:113": {
          "inputs": { "sigmas": "0.909375, 0.725, 0.421875, 0.0" },
          "class_type": "ManualSigmas"
        },
        "153:114": {
          "inputs": { "model_name": "ltx-2.3-spatial-upscaler-x2-1.0.safetensors" },
          "class_type": "LatentUpscaleModelLoader"
        },
        "153:115": {
          "inputs": {
            "positive": ["153:120", 0],
            "negative": ["153:120", 1],
            "latent": ["153:128", 0]
          },
          "class_type": "LTXVCropGuides"
        },
        "153:116": {
          "inputs": {
            "cfg": 1,
            "model": ["153:143", 0],
            "positive": ["153:115", 0],
            "negative": ["153:115", 1]
          },
          "class_type": "CFGGuider"
        },
        "153:117": {
          "inputs": { "upscale_method": "lanczos", "scale_by": 0.5, "image": ["153:124", 0] },
          "class_type": "ImageScaleBy"
        },
        "153:118": {
          "inputs": { "image": ["153:117", 0] },
          "class_type": "GetImageSize"
        },
        "153:119": {
          "inputs": {
            "frames_number": ["153:125", 0],
            "frame_rate": ["153:141", 0],
            "batch_size": 1,
            "audio_vae": ["153:134", 0]
          },
          "class_type": "LTXVEmptyLatentAudio"
        },
        "153:120": {
          "inputs": {
            "frame_rate": ["153:140", 0],
            "positive": ["153:132", 0],
            "negative": ["153:123", 0]
          },
          "class_type": "LTXVConditioning"
        },
        "153:121": {
          "inputs": {
            "width": ["153:118", 0], "height": ["153:118", 1],
            "length": ["153:125", 0], "batch_size": 1
          },
          "class_type": "EmptyLTXVLatentVideo"
        },
        "153:122": {
          "inputs": { "video_latent": ["153:121", 0], "audio_latent": ["153:119", 0] },
          "class_type": "LTXVConcatAVLatent"
        },
        "153:123": {
          "inputs": {
            "text": "blurry, low quality, still frame, frames, watermark, overlay, titles, has blurbox, has subtitles",
            "clip": ["153:147", 0]
          },
          "class_type": "CLIPTextEncode"
        },
        "153:125": {
          "inputs": { "value": 121 },
          "class_type": "PrimitiveInt"
        },
        "153:126": {
          "inputs": {
            "noise": ["153:151", 0], "guider": ["153:139", 0],
            "sampler": ["153:144", 0], "sigmas": ["153:112", 0],
            "latent_image": ["153:122", 0]
          },
          "class_type": "SamplerCustomAdvanced"
        },
        "153:127": { "inputs": { "noise_seed": 0 }, "class_type": "RandomNoise" },
        "153:128": {
          "inputs": { "av_latent": ["153:126", 0] },
          "class_type": "LTXVSeparateAVLatent"
        },
        "153:129": {
          "inputs": { "video_latent": ["153:130", 0], "audio_latent": ["153:128", 1] },
          "class_type": "LTXVConcatAVLatent"
        },
        "153:130": {
          "inputs": {
            "samples": ["153:115", 2],
            "upscale_model": ["153:114", 0],
            "vae": ["153:146", 2]
          },
          "class_type": "LTXVLatentUpsampler"
        },
        "153:131": {
          "inputs": {
            "noise": ["153:127", 0], "guider": ["153:116", 0],
            "sampler": ["153:145", 0], "sigmas": ["153:113", 0],
            "latent_image": ["153:129", 0]
          },
          "class_type": "SamplerCustomAdvanced"
        },
        "153:132": {
          "inputs": {
            "text": "A golden retriever running on a sunlit beach, ocean waves crashing behind it. The dogs fur blows in the wind as it bounds across the sand.",
            "clip": ["153:147", 0]
          },
          "class_type": "CLIPTextEncode"
        },
        "153:133": {
          "inputs": { "fps": ["153:140", 0], "images": ["153:137", 0], "audio": ["153:138", 0] },
          "class_type": "CreateVideo"
        },
        "153:134": {
          "inputs": { "ckpt_name": "ltx-2.3-22b-distilled.safetensors" },
          "class_type": "LTXVAudioVAELoader"
        },
        "153:135": {
          "inputs": { "av_latent": ["153:131", 1] },
          "class_type": "LTXVSeparateAVLatent"
        },
        "153:137": {
          "inputs": {
            "tile_size": 512, "overlap": 64, "temporal_size": 4096, "temporal_overlap": 8,
            "samples": ["153:135", 0], "vae": ["153:146", 2]
          },
          "class_type": "VAEDecodeTiled"
        },
        "153:138": {
          "inputs": { "samples": ["153:135", 1], "audio_vae": ["153:134", 0] },
          "class_type": "LTXVAudioVAEDecode"
        },
        "153:139": {
          "inputs": {
            "cfg": 4, "model": ["153:146", 0],
            "positive": ["153:120", 0], "negative": ["153:120", 1]
          },
          "class_type": "CFGGuider"
        },
        "153:140": { "inputs": { "value": 24 }, "class_type": "PrimitiveFloat" },
        "153:141": { "inputs": { "value": 24 }, "class_type": "PrimitiveInt" },
        "153:143": {
          "inputs": {
            "lora_name": "ltx-2.3-22b-distilled-lora-384.safetensors",
            "strength_model": 1,
            "model": ["153:146", 0]
          },
          "class_type": "LoraLoaderModelOnly"
        },
        "153:144": { "inputs": { "sampler_name": "euler_ancestral" }, "class_type": "KSamplerSelect" },
        "153:145": { "inputs": { "sampler_name": "euler_ancestral" }, "class_type": "KSamplerSelect" },
        "153:151": { "inputs": { "noise_seed": 0 }, "class_type": "RandomNoise" },
        "153:124": {
          "inputs": { "width": 640, "height": 480, "batch_size": 1, "color": 0 },
          "class_type": "EmptyImage"
        },
        "153:146": {
          "inputs": { "ckpt_name": "ltx-2.3-22b-distilled.safetensors" },
          "class_type": "CheckpointLoaderSimple"
        },
        "153:147": {
          "inputs": {
            "text_encoder": "gemma_3_12B_it_fp4_mixed.safetensors",
            "ckpt_name": "ltx-2.3-22b-distilled.safetensors",
            "device": "default"
          },
          "class_type": "LTXAVTextEncoderLoader"
        }
      }
    }
  }'
```

### 4.3 Check Job Status

```bash
# Check status (replace JOB_ID with the id from the /run response)
curl "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/status/JOB_ID" \
  -H "Authorization: Bearer YOUR_RUNPOD_API_KEY"
```

### 4.4 Workflow Parameters

Key parameters you can adjust in the workflow:

| Parameter | Node | Description | Default |
|-----------|------|-------------|---------|
| `text` (prompt) | `153:132` CLIPTextEncode | Text prompt describing the video | — |
| `text` (negative) | `153:123` CLIPTextEncode | Negative prompt | blurry, low quality... |
| `width` / `height` | `153:124` EmptyImage | Base resolution (upscaled 2x) | 640×480 |
| `value` (length) | `153:125` PrimitiveInt | Frame count (must be divisible by 8 + 1) | 121 |
| `value` (frame rate) | `153:140` / `153:141` | FPS (must match in both float and int nodes) | 24 |
| `noise_seed` | `153:151` / `153:127` | Random seed (0 for random) | 0 |
| `steps` | `153:112` LTXVScheduler | Diffusion steps for first pass | 20 |
| `cfg` | `153:139` CFGGuider | CFG scale for first pass | 4 |
| `cfg` (upscale) | `153:116` CFGGuider | CFG scale for upscale pass | 1 |

> **Resolution:** Width & height must be divisible by 32. Frame count must be divisible by 8 + 1 (e.g. 9, 17, 25, ..., 121). Invalid parameters are silently rounded to the nearest valid value.

### 4.5 Synchronous vs Async Requests

Video generation typically takes **1–5 minutes** depending on resolution and frame count.

- **`/run`** (async, recommended): Returns immediately with a job ID. Poll `/status` for results.
- **`/runsync`**: Blocks until complete. May time out for long videos. Has a 20 MB response limit.

For video output, **always use `/run`** with status polling, and configure S3 upload for reliable delivery of large video files.

---

## API Specification

### Input

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| input.workflow | Object | Yes | ComfyUI workflow in API format |
| input.images | Array | No | Input images as {name, image} objects (for image-to-video) |
| input.images[].name | String | Yes | Filename referenced in the workflow |
| input.images[].image | String | Yes | Base64 encoded image string |
| input.comfy_org_api_key | String | No | Per-request Comfy.org API key |

### Output

```json
{
  "id": "sync-uuid-string",
  "status": "COMPLETED",
  "output": {
    "videos": [
      {
        "filename": "video/LTX-2.3_00001_.mp4",
        "type": "base64",
        "data": "AAAAIGZ0eXBpc29t..."
      }
    ]
  },
  "delayTime": 123,
  "executionTime": 120000
}
```

| Field | Type | Description |
|-------|------|-------------|
| output.videos | Array | Generated videos |
| output.videos[].filename | String | Filename assigned by ComfyUI |
| output.videos[].type | String | "base64" or "s3_url" (if S3 configured) |
| output.videos[].data | String | Base64 string or S3 URL |
| output.images | Array | Generated images (if workflow includes SaveImage) |
| output.errors | Array | Non-fatal errors/warnings (if any) |

> **Note:** Video files can be large. Configure S3 upload for production use to avoid response size limits.

---

## Environment Variables

### Required

None. The endpoint works out of the box with no environment variables.

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| **S3 Upload** | | |
| BUCKET_ENDPOINT_URL | S3 endpoint URL (enables S3 upload) | — |
| BUCKET_ACCESS_KEY_ID | AWS access key ID | — |
| BUCKET_SECRET_ACCESS_KEY | AWS secret access key | — |
| **General** | | |
| COMFY_ORG_API_KEY | Comfy.org API key for API Nodes | — |
| COMFY_LOG_LEVEL | Logging: DEBUG, INFO, WARNING, ERROR | DEBUG |
| REFRESH_WORKER | Restart worker after each job (true/false) | false |
| **Advanced** | | |
| WEBSOCKET_RECONNECT_ATTEMPTS | Websocket reconnection attempts | 5 |
| WEBSOCKET_RECONNECT_DELAY_S | Delay between reconnection attempts (seconds) | 3 |
| WEBSOCKET_TRACE | Enable websocket frame tracing | false |

---

## Cost Estimates

### RTX PRO 6000 Blackwell 96GB (recommended)

| Worker Type | Hourly Rate | ~2 min Generation | ~5 min Generation |
|-------------|------------|--------------------|--------------------|
| **Flex** (scale to zero) | ~$2.49/hr | ~$0.08 | ~$0.21 |
| **Active** (always on) | ~$1.99/hr | ~$0.07 | ~$0.17 |

### A100 80GB (alternative)

| Worker Type | Hourly Rate | ~2 min Generation | ~5 min Generation |
|-------------|------------|--------------------|--------------------|
| **Flex** (scale to zero) | $2.72/hr | ~$0.09 | ~$0.23 |
| **Active** (always on) | $2.17/hr | ~$0.07 | ~$0.18 |

> **Note:** Pricing varies. Check [RunPod pricing](https://www.runpod.io/pricing) for current rates.

### Recommended Configuration

| Use Case | Min Workers | Max Workers | Approx. Monthly Cost |
|----------|------------|-------------|---------------------|
| **Development/testing** | 0 (Flex) | 1 | Pay per request only |
| **Low traffic** | 0 (Flex) | 1 | Pay per request only |
| **Production** (instant response) | 1 (Active) | 3 | ~$1,433/mo base + Flex overflow |

---

## Troubleshooting

### Cold Start Takes Too Long

The first-ever cold start pulls the Docker image (~65–75 GB). Subsequent cold starts only load the model (~2–5 min). To eliminate cold starts entirely, set `Min Workers: 1` (Active worker) — but this costs $2.17/hr+ continuously.

### OOM (Out of Memory)

The model requires 32 GB+ VRAM. The RTX PRO 6000 96GB has plenty of headroom (96 GB), but on smaller GPUs (A100 40GB) you may OOM with large resolutions or long videos:
- Reduce `width`/`height` in the EmptyImage node
- Reduce frame count (`value` in the PrimitiveInt Length node)
- Use RTX PRO 6000 96GB or A100 80GB instead of 40GB

### No Video Output / "success_no_output"

If the endpoint returns no output:
1. **Check model names** — ensure the workflow references the exact filenames baked into the image:
   - `ltx-2.3-22b-distilled.safetensors` (checkpoint)
   - `gemma_3_12B_it_fp4_mixed.safetensors` (text encoder)
   - `ltx-2.3-22b-distilled-lora-384.safetensors` (LoRA)
   - `ltx-2.3-spatial-upscaler-x2-1.0.safetensors` (upscaler)
2. **Check logs** — look for `execution_error` messages in the RunPod logs
3. **Verify workflow** — use ComfyUI's `Workflow → Export (API)` to get a clean API format

### Docker Push 502 Errors

Docker Hub's backend struggles with large layers. Retry the push — Docker skips already-uploaded layers:

```bash
docker push your-username/worker-comfyui:latest-ltx-2.3
```

If it keeps failing, push to GHCR instead (see Step 2).

### Video Too Large for Response

RunPod has response size limits (~20 MB for `/runsync`). For production:
1. Configure S3 upload (`BUCKET_ENDPOINT_URL`, `BUCKET_ACCESS_KEY_ID`, `BUCKET_SECRET_ACCESS_KEY`)
2. Use `/run` (async) instead of `/runsync`
3. Reduce resolution or frame count for smaller output files

### CUDA Error: No Kernel Image Available (RTX PRO 6000 / Blackwell)

```
NVIDIA RTX PRO 6000 Blackwell Server Edition with CUDA capability sm_120 is not compatible
The current PyTorch install supports CUDA capabilities sm_50 sm_60 sm_70 sm_75 sm_80 sm_86 sm_90
```

This means the Docker image was built with CUDA 12.6 (supports up to sm_90) but is running on a Blackwell GPU (sm_120). You must rebuild the image with CUDA 12.8:

```bash
export CUDA_LEVEL=12.8
# Then re-run the build script
cd /tmp && curl -fsSL "https://raw.githubusercontent.com/Jmendapara/ltx-video-runpod-worker/main/scripts/build-on-pod.sh?ts=$(date +%s)" | bash
```

---

## Alternative: Deploy on a GPU Pod (Interactive)

If the serverless deployment isn't working or you need to debug interactively, run ComfyUI with the full web UI on a RunPod GPU Pod.

### Create the Pod

1. Go to [RunPod Pods Console](https://www.runpod.io/console/pods)
2. Click **+ GPU Pod**
3. Configure:

| Setting | Value |
|---------|-------|
| GPU | RTX PRO 6000 Blackwell 96GB (or A100 80GB) |
| Template | ComfyUI (RunPod's official template) |
| Container Disk | 100 GB |
| Volume Disk | 80 GB |
| Expose HTTP Ports | 8188 |

4. Click **Deploy**

### Run the Setup Script

```bash
curl -fsSL "https://raw.githubusercontent.com/Jmendapara/ltx-video-runpod-worker/main/scripts/setup-pod.sh?ts=$(date +%s)" | bash
```

This installs ComfyUI, ComfyUI-LTXVideo nodes, downloads all models (~55 GB, takes 15–30 min), and starts ComfyUI on port 8188.

### Access the Web UI

Click **Connect** on your pod in the RunPod dashboard, then click the **HTTP 8188** link.

### Stop the Pod When Done

Pods charge continuously while running. **Stop or delete the pod** when you're done. The model stays on the persistent volume — next time you start the pod, re-run the setup script and it skips the download.

---

## Getting the Workflow JSON

To create your own workflow:

1. Open ComfyUI in a browser
2. Install the [ComfyUI-LTXVideo](https://github.com/Lightricks/ComfyUI-LTXVideo) custom nodes
3. Build your workflow using the LTXVideo nodes
4. Go to **Workflow → Export (API)**
5. Use the exported JSON as the `input.workflow` value in your API requests

See `test_resources/workflows/` for example workflows.

---

## Other Docker Targets

This repo supports multiple ComfyUI model types. Build with `MODEL_TYPE` (or the corresponding docker-bake target):

| MODEL_TYPE | Description | Approx. Image Size | Min GPU |
|------------|-------------|--------------------|---------| 
| base | ComfyUI only, no models | ~8 GB | Any |
| sdxl | Stable Diffusion XL | ~15 GB | 16 GB+ |
| sd3 | Stable Diffusion 3 (needs HF token) | ~12 GB | 16 GB+ |
| flux1-schnell | FLUX.1 schnell (needs HF token) | ~20 GB | 24 GB+ |
| flux1-dev | FLUX.1 dev (needs HF token) | ~20 GB | 24 GB+ |
| flux1-dev-fp8 | FLUX.1 dev FP8 quantized | ~15 GB | 24 GB+ |
| z-image-turbo | Z-Image Turbo | ~15 GB | 24 GB+ |
| **ltx-2.3** | **LTX-2.3 22B distilled (this worker)** | **~65–75 GB** | **RTX PRO 6000 96GB** (CUDA 12.8) or A100 40GB+ (CUDA 12.6) |
| hunyuan-instruct-nf4 | HunyuanImage 3.0 Instruct NF4 | ~119 GB | A100 80GB |
| hunyuan-instruct-int8 | HunyuanImage 3.0 Instruct INT8 | ~155 GB | 96 GB+ |
