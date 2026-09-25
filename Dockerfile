# llama-cpp-sm89-docker
#
# Custom llama.cpp server image built with CMAKE_CUDA_ARCHITECTURES=89
# for **Ada Lovelace** GPUs (RTX 4060 Ti / 4070 / 4080 / 4090, L4 / L40 / L40S,
# RTX 4000/4500/5000/6000 Ada).
#
# The official ghcr.io/ggml-org/llama.cpp:server-cuda image dropped sm_89
# support around mid-2026 (only sm_50/61/70/75/80 + compute_80 PTX in
# current builds). This image recompiles from upstream master with the
# sm_89 arch explicitly set, so it actually works on RTX 40-series cards.
#
# Built automatically by .github/workflows/build-sm89.yml and pushed to:
#   ghcr.io/Chyrain/llama-cpp-sm89-docker:sm89-latest
#
# Build is rebuilt weekly (Monday 06:17 UTC) and on every push to this
# Dockerfile / the workflow file.

ARG CUDA_VERSION=12.8.1
ARG UBUNTU_VERSION=24.04
ARG CUDA_DOCKER_ARCH=89
ARG LLAMA_REF=master

# ============================================================
# Stage 1: clone llama.cpp source (shared by web + build stages)
# ============================================================
FROM alpine:3.20 AS src
ARG LLAMA_REF
RUN apk add --no-cache git ca-certificates && \
    git clone --depth 1 --branch "${LLAMA_REF}" \
        https://github.com/ggml-org/llama.cpp.git /src

# ============================================================
# Stage 2: build the web UI assets (server's web/index.html etc.)
# ============================================================
FROM docker.io/node:24 AS web
COPY --from=src /src /src
WORKDIR /src/tools/ui
RUN npm ci && \
    LLAMA_BUILD_NUMBER=custom-sm89 npm run build

# ============================================================
# Stage 3: compile llama.cpp with CUDA sm_89
# ============================================================
FROM docker.io/nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS build
ARG GCC_VERSION=14
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
COPY --from=src /src /app
COPY --from=web /src/tools/ui/dist /app/tools/ui/dist

# The actual sm_89 compile:
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
    cmake --build build --config Release -j$(nproc)

# ============================================================
# Stage 4: minimal runtime — server + libs only
# ============================================================
FROM docker.io/nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION} AS server

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libgomp1 curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ENV LLAMA_ARG_HOST=0.0.0.0 \
    LLAMA_ARG_PORT=8000

# Copy binary + dynamic libs from build stage
COPY --from=build /app/build/bin/llama-server  /app/llama-server
COPY --from=build /app/build/bin/llama-cli     /app/llama-cli
COPY --from=build /app/build/bin/llama-gguf-hash /app/llama-gguf-hash
COPY --from=build /app/build/libggml.so        /app/libggml.so
COPY --from=build /app/build/libggml-base.so   /app/libggml-base.so
COPY --from=build /app/build/libggml-cpu.so    /app/libggml-cpu.so
COPY --from=build /app/build/libggml-cuda.so   /app/libggml-cuda.so

WORKDIR /app

HEALTHCHECK CMD [ "curl", "-f", "http://localhost:8080/health" ]

ENTRYPOINT [ "/app/llama-server" ]
