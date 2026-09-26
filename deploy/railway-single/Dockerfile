# Vellum Assistant — single-container build for Railway.
# Railway can't share localhost between services, so the three official
# images (gateway, credential-executor, assistant) are merged into one and
# supervised by railway-start.sh. Bump VELLUM_VERSION to upgrade.
ARG VELLUM_VERSION=v0.12.5

FROM vellumai/vellum-gateway:${VELLUM_VERSION} AS gateway
FROM vellumai/vellum-credential-executor:${VELLUM_VERSION} AS ces

FROM vellumai/vellum-assistant:${VELLUM_VERSION}
USER root

COPY --from=gateway /app /opt/gateway-app
COPY --from=ces /app /opt/ces-app
COPY railway-start.sh /usr/local/bin/railway-start
RUN chmod +x /usr/local/bin/railway-start

# Cloudflare Tunnel connector (runs when TUNNEL_TOKEN is set).
RUN arch="$(dpkg --print-architecture)" && \
    curl -fsSL -o /usr/local/bin/cloudflared \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" && \
    chmod +x /usr/local/bin/cloudflared && cloudflared --version

ENV IS_CONTAINERIZED=true \
    DEBUG_STDOUT_LOGS=1 \
    VELLUM_CLOUD=docker \
    VELLUM_DATA_DIR=/data \
    GATEWAY_PORT=7830 \
    RUNTIME_HTTP_PORT=7821

EXPOSE 7830
CMD ["/usr/local/bin/railway-start"]
