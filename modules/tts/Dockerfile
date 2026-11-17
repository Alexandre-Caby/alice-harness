ARG UBUNTU_IMAGE
FROM ${UBUNTU_IMAGE}
ARG QWEN_TTS_COMMIT
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates libopenblas-dev pkg-config \
 && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/gabriele-mastrapasqua/qwen3-tts /src && cd /src && git checkout "$QWEN_TTS_COMMIT" \
 && make blas
# Open WebUI always sends a voice name: fall back to the loaded voice instead of failing.
ENV QWEN_SERVER_STRICT=0
USER 65534:65534
ENTRYPOINT ["/src/qwen_tts"]
