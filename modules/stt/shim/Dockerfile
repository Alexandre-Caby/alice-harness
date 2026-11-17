ARG PYTHON_IMAGE
FROM ${PYTHON_IMAGE}
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
COPY server.py /opt/stt/server.py
USER 65534:65534
ENTRYPOINT ["python3", "-I", "/opt/stt/server.py"]
