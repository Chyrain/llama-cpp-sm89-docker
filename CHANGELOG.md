# Changelog

All notable changes to this image are documented here.

## 2026-09-25 — Initial release

**First cut.**

- Recompiles llama.cpp from upstream `master` with `CMAKE_CUDA_ARCHITECTURES=89`.
- Mirrors the official `.devops/cuda.Dockerfile` structure, with sm_89 forced on.
- Pushed to `ghcr.io/Chyrain/llama-cpp-sm89-docker:sm89-latest`.
- Weekly rebuild + on-push to Dockerfile / workflow file.
- Manual trigger via `workflow_dispatch` with optional `tag` and `llama_ref` inputs.

## Use case

NAS at `192.168.1.2` has an RTX 4060 Ti (sm_89). The official `ghcr.io/ggml-org/llama.cpp:server-cuda`
image (b9828, June 2026) supports sm_89 but lacks `qwen35` architecture (Qwen3.8-27B,
Ornith-1.5-9B). Newer official builds (b4721+) have `qwen35` but no sm_89 kernel → SIGSEGV.

This image bridges that gap.

## Smoke-test procedure

After the GH Actions run completes:

```bash
docker pull ghcr.io/Chyrain/llama-cpp-sm89-docker:sm89-latest

# On the NAS:
docker run --rm --gpus all \
  -v /vol3/1000/disk3/Models/yuxinlu1-gemma-4-12B-coder-v1-GGUF:/models:ro \
  ghcr.io/Chyrain/llama-cpp-sm89-docker:sm89-latest \
  -m /models/gemma4-coding-Q4_K_M.gguf -ngl 999 -c 4096 \
  --flash-attn --jinja --port 8000 2>&1 | grep -E "(ARCHS|loaded|listening)"
```

Expected:

```
CUDA : ARCHS = …,890,…      # contains sm_89
model loaded
server is listening on http://0.0.0.0:8080
```

## KNOWN LIMITATIONS

- **Multimodal `--mmproj` removed**: upstream removed the `--mmproj` parameter from server
  builds (use `llama-mtmd-cli` instead, or fall back to old b9828 image).
- **b9828 image still required for mmproj vision workloads**.
- **No sm_90/sm_100/sm_120 kernels**: this image is sm_89-only by design. Cross-flavor
  deployments (Hopper, Blackwell) need separate images.
