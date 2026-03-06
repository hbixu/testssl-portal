# syntax=docker/dockerfile:1.4
# testssl-portal: testssl.sh + webfrontend (i18n, branding).
# Build: docker build -f Dockerfile --build-arg TESTSSL_REF=3.2 -t testssl-portal .
# Run:   docker run -d -p 5000:5000 -e BRANDING_LABEL="TLS/SSL Server Checker" -e DEFAULT_LOCALE=pt-PT testssl-portal

# ---- Builder: testssl.sh (version configurable) ----
FROM debian:bookworm-slim AS testssl-builder
ENV DEBIAN_FRONTEND=noninteractive

ARG TESTSSL_REF=3.2

RUN apt-get update -y && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 5 --branch="${TESTSSL_REF}" https://github.com/testssl/testssl.sh.git /testssl.sh \
    && (cd /testssl.sh && git log -n 5 > testssl-changelog.txt) \
    && rm -rf /testssl.sh/.git /testssl.sh/bin/openssl.Darwin.* /testssl.sh/bin/openssl.FreeBSD.*

# ---- Builder: webfrontend from context ----
ARG APP_PATH=webfrontend
FROM debian:bookworm-slim AS app-builder
ARG APP_PATH=webfrontend
COPY ${APP_PATH}/ /app/

# ---- Final image ----
# Python is required: Flask backend runs testssl.sh, validates form, streams output via aha, serves i18n/branding.
# Using debian:bookworm-slim + --no-install-recommends to keep image smaller; Alpine would be smaller but testssl.sh (bash/GNU) compatibility must be verified.
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive

ARG BUILD_DATE
ARG VERSION
ARG TESTSSL_REF=3.2
ENV TESTSSL_VERSION=${TESTSSL_REF}
ENV PORTAL_VERSION=${VERSION}
LABEL maintainer="hugobicho@gmail.com"
# LABEL org.opencontainers.image.source="https://github.com/your-username/testssl-portal"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.version="${VERSION}"

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
        coreutils \
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

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
