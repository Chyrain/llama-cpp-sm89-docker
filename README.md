# llama-cpp-sm89-docker

Custom **llama.cpp server** Docker image built with `CMAKE_CUDA_ARCHITECTURES=89`
so it runs on Ada Lovelace GPUs (RTX 40-series, L4/L40/L40S, RTX 4000/4500/5000/6000 Ada).

## Why this exists

The official `ghcr.io/ggml-org/llama.cpp:server-cuda` image dropped **sm_89** support
around mid-2026. Newer builds (`b4721`+) only ship kernels for sm_50/61/70/75/80
plus a `compute_80` PTX fallback. Loading any GPU model on an RTX 40-series card
segfaults at `print_info: file size …` because there's no sm_89 binary and the
PTX only JITs to sm_80 or below.

This repo recompiles llama.cpp from upstream `master` with `CMAKE_CUDA_ARCHITECTURES=89`
forced on, producing an image that **actually works** on Ada cards.

## Pull & run

```bash
docker pull ghcr.io/Chyrain/llama-cpp-sm89-docker:sm89-latest

docker run --rm --gpus all \
  -v /path/to/models:/models:ro \
  -p 8080:8080 \
  ghcr.io/Chyrain/llama-cpp-sm89-docker:sm89-latest \
  -m /models/your-model.gguf \
  -ngl 999 \
  -c 32768 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --flash-attn --jinja \
  --host 0.0.0.0 --port 8080
```

## What's built in

- **Base image**: `nvidia/cuda:12.8.1-runtime-ubuntu24.04` (matches the dev stage)
- **CUDA arch**: `sm_89` (Ada Lovelace)
- **Toolchain**: gcc-14 + nvcc (CUDA 12.8.1)
- **llama.cpp source**: `master` at build time (default), overridable via workflow input
- **Binary**: `/app/llama-server`, plus `llama-cli` and `llama-gguf-hash` for debugging
- **Default entrypoint**: `llama-server` listening on `0.0.0.0:8080`
- **Healthcheck**: `curl -f http://localhost:8080/health`

> Note: **multimodal `--mmproj` is disabled in current upstream server builds.**
> If you need vision input, fall back to the old `ghcr.io/ggml-org/llama.cpp:server-cuda`
> (b9828 / GGUF v9828, no qwen35 architecture) or use `llama-mtmd-cli` directly.

## Verify it works on your hardware

After pulling, smoke-test:

```bash
docker run --rm --gpus all \
  ghcr.io/Chyrain/llama-cpp-sm89-docker:sm89-latest \
  -m /models/some-model.gguf -ngl 1 -c 256 2>&1 | grep "ARCHS"
```

You should see:

```
CUDA : ARCHS = …,890,…   ← contains 890 (sm_89)
```

## Rebuild cadence

- **Weekly**: every Monday 06:17 UTC (cron) — pulls latest master
- **Manual**: Actions → "build-sm89" → Run workflow (optional `tag` and `llama_ref` inputs)
- **On change**: any push to this Dockerfile or `.github/workflows/build-sm89.yml`

## Build locally

```bash
docker build \
  --build-arg CUDA_DOCKER_ARCH=89 \
  --build-arg LLAMA_REF=master \
  -t llama-cpp-sm89:dev \
  .

docker run --rm --gpus all \
  -v /path/to/models:/models:ro \
  -p 8080:8080 \
  llama-cpp-sm89:dev \
  -m /models/your-model.gguf -ngl 999
```

## Provenance

- **Built by**: GitHub Actions (see `.github/workflows/build-sm89.yml`)
- **Source**: <https://github.com/ggml-org/llama.cpp> (Apache-2.0)
- **Dockerfile**: based on the official `ggml-org/llama.cpp/.devops/cuda.Dockerfile`
- **Differences from upstream**: sm_89 hard-coded, no mmproj (upstream removed)

## See also

- Issue tracking upstream sm_89 removal: <https://github.com/ggml-org/llama.cpp/issues>
- Original research: `~/Desktop/workspace/AI/iwork/FNOSAgentWorkspace/docs/models/MODEL_LIBRARY_ANALYSIS.md`
