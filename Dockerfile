# syntax=docker/dockerfile:1.4
# testssl-portal: testssl.sh + webfrontend (i18n, branding).
# Build: docker build -f Dockerfile --build-arg TESTSSL_VERSION=3.2 -t testssl-portal .
# Run:   docker run -d -p 5000:5000 -e BRANDING_LABEL="TLS/SSL Server Checker" -e DEFAULT_LOCALE=pt-PT testssl-portal

# ==============================================================================
# Base Image Version
# Repository: https://hub.docker.com/_/debian/tags?name=bookworm
# Format: bookworm-YYYYMMDD-slim (pinned) or bookworm-slim (rolling)
# Check versions: ./check-versions.sh
# ==============================================================================
ARG BASEIMAGE_VERSION=bookworm-20250224-slim

# ---- Builder: testssl.sh (version configurable) ----
FROM debian:${BASEIMAGE_VERSION} AS testssl-builder
ENV DEBIAN_FRONTEND=noninteractive

# ==============================================================================
# Component Versions
# testssl.sh: https://github.com/testssl/testssl.sh/releases
# Check versions: curl -s https://api.github.com/repos/testssl/testssl.sh/releases/latest | grep tag_name
# Branches: 3.0, 3.2, main (development)
# ==============================================================================
ARG TESTSSL_VERSION=3.2

RUN apt-get update -y && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 5 --branch="${TESTSSL_VERSION}" https://github.com/testssl/testssl.sh.git /testssl.sh \
    && (cd /testssl.sh && git log -n 5 > testssl-changelog.txt) \
    && rm -rf /testssl.sh/.git /testssl.sh/bin/openssl.Darwin.* /testssl.sh/bin/openssl.FreeBSD.*

# ---- Builder: webfrontend from context ----
ARG APP_PATH=webfrontend
ARG BASEIMAGE_VERSION=bookworm-slim
FROM debian:${BASEIMAGE_VERSION} AS app-builder
ARG APP_PATH=webfrontend
COPY ${APP_PATH}/ /app/

# ---- Final image ----
# Python is required: Flask backend runs testssl.sh, validates form, streams output via aha, serves i18n/branding.
# Using debian:bookworm-slim + --no-install-recommends to keep image smaller; Alpine would be smaller but testssl.sh (bash/GNU) compatibility must be verified.
ARG BASEIMAGE_VERSION=bookworm-slim
FROM debian:${BASEIMAGE_VERSION}
ENV DEBIAN_FRONTEND=noninteractive

# Image metadata ARGs
ARG BUILD_DATE
ARG VERSION=1.0.0
ARG TESTSSL_VERSION=3.2
ARG BASEIMAGE_VERSION

# Runtime environment
ENV TESTSSL_VERSION=${TESTSSL_VERSION}
ENV PORTAL_VERSION=${VERSION}

# OCI Image Labels
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.title="testssl-portal" \
      org.opencontainers.image.description="Web portal for TLS/SSL server testing using testssl.sh" \
      org.opencontainers.image.vendor="Hugo Santos" \
      org.opencontainers.image.authors="hugobicho@gmail.com" \
      org.opencontainers.image.licenses="GPL-3.0" \
      org.opencontainers.image.baseimage.version="${BASEIMAGE_VERSION}" \
      org.opencontainers.image.baseimage.name="debian" \
      org.opencontainers.image.testssl.version="${TESTSSL_VERSION}"

ENV UWSGI_PROCESSES=4
ENV UWSGI_THREADS=2
ENV TEST_TIMEOUT=300
ENV TESTSSLDEBUG=0

ENV BRANDING_LABEL="TLS/SSL Server Checker"
ENV BRANDING_ICON_URL=""
ENV BRANDING_LINK=""
ENV DEFAULT_LOCALE=pt-PT

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
        openssl net-tools dnsutils aha xxd python3-flask \
        bsdmainutils procps nginx-light uwsgi uwsgi-plugin-python3 supervisor socat \
        coreutils curl \
    && apt-get purge -y --auto-remove \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*

COPY nginx.conf /etc/nginx/
COPY testssl.conf /etc/nginx/sites-enabled/default
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY uwsgi.ini /etc/uwsgi/
COPY entrypoint.sh /

COPY --from=testssl-builder /testssl.sh /testssl.sh
COPY --from=app-builder /app /testssl

WORKDIR /testssl
EXPOSE 5000

VOLUME ["/testssl/static/custom"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
