ARG PASEO_VERSION=latest
FROM ghcr.io/getpaseo/paseo:${PASEO_VERSION}

COPY install.sh /usr/local/bin/install.sh
RUN chmod +x /usr/local/bin/install.sh && \
    install.sh setup-bash-wrap

USER paseo
