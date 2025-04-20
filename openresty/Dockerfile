FROM bitnami/openresty:1.27.1-1-debian-12-r5

USER root

RUN apt-get update && apt-get install -y \
    curl unzip git iputils-ping \
 && opm get ledgetech/lua-resty-http \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
