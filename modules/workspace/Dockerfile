ARG OPEN_TERMINAL_IMAGE
FROM ${OPEN_TERMINAL_IMAGE}
USER root
RUN apt-get update && apt-get install -y --no-install-recommends cargo rustc && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir pytest==9.2.0 pdfplumber==0.11.10 reportlab==5.1.0
# The bundled python has a file capability that no-new-privileges refuses to exec; only multi-user mode needs it.
RUN sed -i '1s|.*|#!/usr/local/bin/python3|' /usr/local/bin/open-terminal
USER user
# No browser or desktop control; no pager, which would hang a command waiting for a key.
ENV OPEN_TERMINAL_ENABLE_BROWSER=false OPEN_TERMINAL_ENABLE_DESKTOP=false PAGER=cat GIT_PAGER=cat
