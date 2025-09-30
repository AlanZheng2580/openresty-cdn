# FROM bitnami/openresty:1.27.1-1-debian-12-r5

# USER root

# RUN apt-get update && apt-get install -y \
#     curl unzip git iputils-ping \
#  && opm get ledgetech/lua-resty-http \
#  && apt-get clean && rm -rf /var/lib/apt/lists/*


FROM cyching/openresty:20250923-710ff5cf-1.27.1-2-debian-12-r15

USER root

RUN sed -i '/exec "\$@"/i \
# Check if SECDN_APIKEY_DIR exists and is a directory\n\
if [ -z "$SECDN_APIKEY_DIR" ] || [ ! -d "$SECDN_APIKEY_DIR" ]; then\n\
  echo "[FATAL] SECDN_APIKEY_DIR is not set or not a directory!" >&2\n\
  exit 1\n\
fi\n\
# Check if MINIO_SECRET_KEY exists\n\
if [ -z "$MINIO_SECRET_KEY" ]; then\n\
  echo "[FATAL] MINIO_SECRET_KEY is not set!" >&2\n\
  exit 1\n\
fi\n\
' /opt/bitnami/scripts/openresty/entrypoint.sh

USER 1001
