# Alpine Migration Plan

This document outlines the migration from `debian:bookworm-slim` to `alpine` as the base image for testssl-portal.

## Motivation

| Metric | Debian bookworm-slim | Alpine | Savings |
|--------|---------------------|--------|---------|
| Base image size | ~75 MB | ~8 MB | ~90% |
| Estimated final image | ~250-300 MB | ~100-150 MB | ~50% |

**Benefits:**
- Smaller image size = faster pulls, less storage
- Smaller attack surface (fewer packages)
- Faster container startup
- Lower bandwidth costs for registries

## Compatibility Analysis

### testssl.sh Requirements

testssl.sh is a bash script that requires:

| Dependency | Debian | Alpine | Notes |
|------------|--------|--------|-------|
| bash | ✅ native | ⚠️ `apk add bash` | Required, busybox sh not sufficient |
| GNU coreutils | ✅ native | ⚠️ `apk add coreutils` | Some GNU-specific flags used |
| openssl | ✅ apt | ✅ `apk add openssl` | Compatible |
| procps | ✅ apt | ✅ `apk add procps` | For ps command |
| net-tools | ✅ apt | ✅ `apk add net-tools` | Optional |
| bind-tools | dnsutils | ✅ `apk add bind-tools` | For dig/nslookup |
| xxd | ✅ apt | ✅ `apk add xxd` | Hex dump utility |
| aha | ✅ apt | ⚠️ build from source | ANSI to HTML (not in Alpine repos) |

### Flask Application Requirements

| Dependency | Debian | Alpine | Notes |
|------------|--------|--------|-------|
| python3 | ✅ apt | ✅ `apk add python3` | Compatible |
| flask | python3-flask | `apk add py3-flask` | Compatible |
| nginx | nginx-light | ✅ `apk add nginx` | Compatible |
| uwsgi | uwsgi + plugin | ✅ `apk add uwsgi uwsgi-python3` | Compatible |
| supervisor | ✅ apt | ✅ `apk add supervisor` | Compatible |
| curl | ✅ apt | ✅ `apk add curl` | For healthcheck |

### Known Compatibility Issues

1. **aha (ANSI to HTML)** - Not in Alpine repos, must build from source or use alternative
2. **musl vs glibc** - Some edge cases in string handling, but testssl.sh should work
3. **busybox vs GNU** - testssl.sh uses GNU-specific flags, need `coreutils` package

## Migration Strategy

### Option A: Direct Alpine Migration (Recommended)

Replace Debian with Alpine, install required packages including bash and coreutils.

**Pros:**
- Smallest image size
- Single base image to maintain

**Cons:**
- Need to build aha from source
- Potential edge cases with musl

### Option B: LinuxServer.io Alpine Base

Use `ghcr.io/linuxserver/baseimage-alpine` which provides s6-overlay init system.

**Pros:**
- Proven init system
- Good for multi-process containers
- Active maintenance

**Cons:**
- Different init system (s6 vs supervisor)
- Requires restructuring entrypoint

### Option C: Hybrid (Multi-stage with Alpine runtime)

Build testssl.sh and dependencies in Debian, copy to Alpine runtime.

**Pros:**
- Ensures testssl.sh compatibility
- Smaller runtime image

**Cons:**
- More complex Dockerfile
- May still have runtime issues

## Recommended Approach: Option A

### New Dockerfile Structure

```dockerfile
# ==============================================================================
# Base Image Version
# Repository: https://hub.docker.com/_/alpine/tags
# Format: X.Y (e.g., 3.21)
# ==============================================================================
ARG BASEIMAGE_VERSION=3.21

# ---- Builder: testssl.sh ----
FROM alpine:${BASEIMAGE_VERSION} AS testssl-builder

ARG TESTSSL_VERSION=v3.2.3

RUN apk add --no-cache git ca-certificates \
    && git clone --depth 5 --branch="${TESTSSL_VERSION}" \
       https://github.com/testssl/testssl.sh.git /testssl.sh \
    && rm -rf /testssl.sh/.git /testssl.sh/bin/openssl.Darwin.* /testssl.sh/bin/openssl.FreeBSD.*

# ---- Builder: aha (ANSI to HTML) ----
FROM alpine:${BASEIMAGE_VERSION} AS aha-builder

RUN apk add --no-cache git make gcc musl-dev \
    && git clone --depth 1 https://github.com/theZiz/aha.git /aha \
    && cd /aha && make

# ---- Builder: webfrontend ----
ARG APP_PATH=webfrontend
FROM alpine:${BASEIMAGE_VERSION} AS app-builder
ARG APP_PATH=webfrontend
COPY ${APP_PATH}/ /app/

# ---- Final image ----
ARG BASEIMAGE_VERSION=3.21
FROM alpine:${BASEIMAGE_VERSION}

ARG BUILD_DATE
ARG VERSION=1.0.0
ARG TESTSSL_VERSION=v3.2.3
ARG BASEIMAGE_VERSION

ENV TESTSSL_VERSION=${TESTSSL_VERSION}
ENV PORTAL_VERSION=${VERSION}

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.title="testssl-portal" \
      org.opencontainers.image.description="Web portal for TLS/SSL server testing using testssl.sh" \
      org.opencontainers.image.vendor="Hugo Santos" \
      org.opencontainers.image.authors="hugobicho@gmail.com" \
      org.opencontainers.image.licenses="GPL-3.0" \
      org.opencontainers.image.baseimage.version="${BASEIMAGE_VERSION}" \
      org.opencontainers.image.baseimage.name="alpine" \
      org.opencontainers.image.testssl.version="${TESTSSL_VERSION}"

# Install runtime dependencies
# bash + coreutils required for testssl.sh GNU compatibility
RUN apk add --no-cache \
    bash coreutils \
    openssl bind-tools xxd \
    python3 py3-flask \
    nginx uwsgi uwsgi-python3 supervisor \
    procps curl socat

# Copy aha from builder
COPY --from=aha-builder /aha/aha /usr/bin/aha

# Configuration files
COPY nginx.conf /etc/nginx/
COPY testssl.conf /etc/nginx/http.d/default.conf
COPY supervisord.conf /etc/supervisor.d/testssl-portal.ini
COPY uwsgi.ini /etc/uwsgi/

# Entrypoint
COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

# Application
COPY --from=testssl-builder /testssl.sh /testssl.sh
COPY --from=app-builder /app /testssl

# Runtime settings
ENV UWSGI_PROCESSES=4
ENV UWSGI_THREADS=2
ENV TEST_TIMEOUT=300
ENV TESTSSLDEBUG=0
ENV BRANDING_LABEL="TLS/SSL Server Checker"
ENV BRANDING_ICON_URL=""
ENV BRANDING_LINK=""
ENV DEFAULT_LOCALE=en

WORKDIR /testssl
EXPOSE 5000
VOLUME ["/testssl/static/custom"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -sf http://localhost:5000/ || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
```

## Configuration Changes Required

### 1. nginx.conf

Alpine nginx uses `/etc/nginx/http.d/` instead of `/etc/nginx/sites-enabled/`:

```nginx
# Change COPY destination
COPY testssl.conf /etc/nginx/http.d/default.conf
```

### 2. supervisord.conf

Alpine supervisor uses `/etc/supervisor.d/` with `.ini` files:

```ini
# Rename to /etc/supervisor.d/testssl-portal.ini
# Update paths if needed
```

### 3. entrypoint.sh

Update nginx config path:

```bash
sed -i "s/@@UWSGI_READ_TIMEOUT@@/${UWSGI_READ_TIMEOUT}/" /etc/nginx/http.d/default.conf
```

## Build Script Changes

### build.sh Updates

```bash
# Change DEFAULT_BASEIMAGE_VERSION format
DEFAULT_BASEIMAGE_VERSION="3.21"  # Alpine uses X.Y format

# Update comments
# Base image: https://hub.docker.com/_/alpine/tags
# Check versions: ./check-versions.sh
```

### check-versions.sh Updates

Add Alpine tag checking:

```bash
check_alpine_tags() {
    local current_tag="$1"
    # Alpine uses simple X.Y versioning
    # Query: https://hub.docker.com/v2/repositories/library/alpine/tags
    # Compare versions numerically
}
```

## Testing Plan

### Phase 1: Build Verification

1. [ ] Build Alpine image successfully
2. [ ] Verify all packages installed
3. [ ] Check image size reduction

### Phase 2: Functional Testing

1. [ ] testssl.sh runs without errors
2. [ ] All scan types work (certificate, normal, full)
3. [ ] STARTTLS protocols work
4. [ ] Output streaming works correctly
5. [ ] ANSI colors render properly (aha)

### Phase 3: Compatibility Testing

1. [ ] Test against various TLS servers
2. [ ] Compare output with Debian version
3. [ ] Verify no regressions in scan results

### Phase 4: Performance Testing

1. [ ] Compare startup time
2. [ ] Compare scan execution time
3. [ ] Compare memory usage

## Rollback Plan

If Alpine migration causes issues:

1. Keep Debian Dockerfile as `Dockerfile.debian`
2. Tag Alpine image as `testssl-portal:alpine`
3. Allow users to choose via build arg or separate tags

## Estimated Timeline

| Phase | Task | Duration |
|-------|------|----------|
| 1 | Create Alpine Dockerfile | 1-2 hours |
| 2 | Update configuration files | 1 hour |
| 3 | Update build/check scripts | 1 hour |
| 4 | Testing & validation | 2-4 hours |
| 5 | Documentation update | 1 hour |

**Total: ~6-9 hours**

## Size Comparison (Estimated)

| Component | Debian | Alpine |
|-----------|--------|--------|
| Base image | 75 MB | 8 MB |
| Python + Flask | 80 MB | 40 MB |
| nginx + uwsgi | 30 MB | 15 MB |
| testssl.sh + openssl | 50 MB | 30 MB |
| Other deps | 15 MB | 7 MB |
| **Total** | **~250 MB** | **~100 MB** |

**Expected reduction: ~60%**

## Decision Checklist

Before proceeding with migration:

- [ ] Confirm testssl.sh works on Alpine (quick test)
- [ ] Verify aha builds successfully on Alpine
- [ ] Check if py3-flask version is acceptable
- [ ] Decide on supervisor vs s6-overlay
- [ ] Review security implications

## References

- [Alpine Linux Packages](https://pkgs.alpinelinux.org/packages)
- [testssl.sh GitHub](https://github.com/testssl/testssl.sh)
- [aha GitHub](https://github.com/theZiz/aha)
- [LinuxServer Alpine Base](https://github.com/linuxserver/docker-baseimage-alpine)
