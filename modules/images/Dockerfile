ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE}
ARG SDCPP_COMMIT
ARG BACKEND=vulkan
RUN apt-get update && apt-get install -y --no-install-recommends build-essential cmake git ca-certificates \
      libvulkan-dev glslc spirv-headers mesa-vulkan-drivers \
 && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/leejet/stable-diffusion.cpp /src && cd /src && git checkout "$SDCPP_COMMIT" \
 && git submodule update --init --recursive
WORKDIR /src
RUN case "$BACKEND" in vulkan) f=-DSD_VULKAN=ON ;; rocm) f=-DSD_HIPBLAS=ON ;; cuda) f=-DSD_CUDA=ON ;; *) f= ;; esac \
 && cmake -B build -DCMAKE_BUILD_TYPE=Release -DSD_SERVER_BUILD_FRONTEND=OFF $f \
 && cmake --build build --target sd-server -j"$(nproc)"
USER 65534:65534
ENTRYPOINT ["/src/build/bin/sd-server"]
