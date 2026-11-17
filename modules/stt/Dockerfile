ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE}
ARG NEMO_SPEECH_COMMIT
ARG BACKEND=vulkan
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build git pkg-config ca-certificates libsentencepiece-dev \
      libvulkan-dev glslc spirv-headers mesa-vulkan-drivers \
 && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/NVIDIA/NeMo-Speech.cpp /src && cd /src && git checkout "$NEMO_SPEECH_COMMIT" \
 && git submodule update --init --depth 1 llama.cpp third_party/cpp-httplib
WORKDIR /src
RUN scripts/configure.sh "${BACKEND}-server" && cmake --build --preset "${BACKEND}-server"
ENV PATH=/src/build/${BACKEND}-server/bin:$PATH HOME=/tmp
USER 65534:65534
ENTRYPOINT ["nemo-speech"]
