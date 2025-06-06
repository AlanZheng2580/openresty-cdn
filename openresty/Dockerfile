# FROM bitnami/openresty:1.27.1-1-debian-12-r5

# USER root

# RUN apt-get update && apt-get install -y \
#     curl unzip git iputils-ping \
#  && opm get ledgetech/lua-resty-http \
#  && apt-get clean && rm -rf /var/lib/apt/lists/*


FROM cyching/openresty:20250526-861eb6ae-1.27.1-1-debian-12-r5

USER root

RUN sed -i '/exec "\$@"/i \
# Check if MINIO_SECRET_KEY exists\n\
if [ -z "$MINIO_SECRET_KEY" ]; then\n\
  echo "[FATAL] MINIO_SECRET_KEY is not set!" >&2\n\
  exit 1\n\
fi\n\
' /opt/bitnami/scripts/openresty/entrypoint.sh

USER 1001
