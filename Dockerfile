# Tesla Dashcam Decryptor - Docker image
# Wraps https://github.com/XGxF3/tesla-dashcam-decrypt (MIT)
FROM python:3.12-slim

# Set to "false" at build time to skip ffmpeg (saves ~150 MB; REMUX will then be unavailable)
ARG INSTALL_FFMPEG=true

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends tini tzdata \
 && if [ "$INSTALL_FFMPEG" = "true" ]; then apt-get install -y --no-install-recommends ffmpeg; fi \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY app/requirements.txt /app/requirements.txt
RUN pip install -r /app/requirements.txt

COPY app/tesla_dashcam_decrypt.py /app/tesla_dashcam_decrypt.py
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# Normalise permissions: files copied from a NAS share can arrive as 600/700,
# which the non-root PUID user can't read.
RUN chmod 755 /app /usr/local/bin/entrypoint.sh \
 && chmod 644 /app/tesla_dashcam_decrypt.py /app/requirements.txt \
 && mkdir -p /input /output

VOLUME ["/input", "/output"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
