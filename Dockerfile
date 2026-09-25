# llama-cpp-sm89-docker
#
# Custom llama.cpp server image built with CMAKE_CUDA_ARCHITECTURES=89
# for **Ada Lovelace** GPUs (RTX 4060 Ti / 4070 / 4080 / 4090, L4 / L40 / L40S,
# RTX 4000/4500/5000/6000 Ada).
#
# Why: the official ghcr.io/ggml-org/llama.cpp:server-cuda image dropped sm_89
# from its default CMAKE_CUDA_ARCHITECTURES around mid-2026. Current official
# builds (b4721+) only ship kernels for sm_50/61/70/75/80 with a compute_80 PTX
# fallback, so loading any GPU model on an RTX 40-series card segfaults right
# after "print_info: file size".
#
# This image recompiles upstream llama.cpp master with sm_89 forced on.
#
# Structure mirrors ggml-org/llama.cpp/.devops/cuda.Dockerfile (upstream
# Apache-2.0), with three changes:
#   1. CUDA_DOCKER_ARCH defaults to 89 (upstream: "default" = all supported)
#   2. llm source ref is configurable via LLAMA_REF
#   3. server-only runtime stage (no python conversion tooling)

ARG CUDA_VERSION=12.8.1
ARG UBUNTU_VERSION=24.04
ARG CUDA_DOCKER_ARCH=89
ARG LLAMA_REF=master
ARG GCC_VERSION=14

# ============================================================
# Stage 1 — source checkout (shared by web + build stages)
# ============================================================
FROM alpine:3.20 AS src
ARG LLAMA_REF
RUN apk add --no-cache git ca-certificates && \
    git clone --depth 1 --branch "${LLAMA_REF}" \
        https://github.com/ggml-org/llama.cpp.git /src

# ============================================================
# Stage 2 — build the bundled web UI
# ============================================================
FROM docker.io/node:24 AS web
WORKDIR /ui
COPY --from=src /src/tools/ui/package.json \
                /src/tools/ui/package-lock.json ./
RUN npm ci
COPY --from=src /src/tools/ui/ ./
RUN LLAMA_BUILD_NUMBER=custom-sm89 npm run build

# ============================================================
# Stage 3 — compile llama.cpp for CUDA sm_89
# ============================================================
FROM docker.io/nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS build
ARG GCC_VERSION
ARG CUDA_DOCKER_ARCH

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc-${GCC_VERSION} g++-${GCC_VERSION} \
        build-essential cmake python3 python3-pip \
        git libssl-dev libgomp1 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ENV CC=gcc-${GCC_VERSION} \
    CXX=g++-${GCC_VERSION} \
    CUDAHOSTCXX=g++-${GCC_VERSION}

WORKDIR /app
COPY --from=src /src .
COPY --from=web /ui/dist tools/ui/dist

# The actual sm_89 compile. CUDA_DOCKER_ARCH=89 expands to
# -DCMAKE_CUDA_ARCHITECTURES=89 → nvcc emits real (sm_89) + compute_89 PTX.
RUN if [ "${CUDA_DOCKER_ARCH}" != "default" ]; then \
      export CMAKE_ARGS="-DCMAKE_CUDA_ARCHITECTURES=${CUDA_DOCKER_ARCH}"; \
    fi && \
    cmake -B build \
      -DGGML_NATIVE=OFF \
      -DGGML_CUDA=ON \
      -DGGML_BACKEND_DL=ON \
      -DGGML_CPU_ALL_VARIANTS=ON \
      -DLLAMA_BUILD_TESTS=OFF \
      ${CMAKE_ARGS} \
      -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined . && \
    cmake --build build --config Release -j"$(nproc)"

# Stage every shared object into one dir, preserving symlinks and
# the per-CPU-variant backends that -DGGML_BACKEND_DL=ON loads at runtime.
RUN mkdir -p /staging/lib && \
    find build -name "*.so*" -exec cp -P {} /staging/lib \; && \
    mkdir -p /staging/bin && \
    cp build/bin/llama-server build/bin/llama-cli build/bin/llama-gguf-hash /staging/bin/ && \
    ls -la /staging/lib | head -30

# ============================================================
# Stage 4 — runtime (server only, no python tooling)
# ============================================================
FROM docker.io/nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION} AS server

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libgomp1 curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Whole lib dir in one COPY so symlinks + CPU variants survive.
COPY --from=build /staging/lib /app/
COPY --from=build /staging/bin /app/

WORKDIR /app

ENV LLAMA_ARG_HOST=0.0.0.0 \
    LLAMA_ARG_PORT=8080

HEALTHCHECK CMD [ "curl", "-f", "http://localhost:8080/health" ]

ENTRYPOINT [ "/app/llama-server" ]
