# Plan: Rootless Container

This document outlines the plan to run the testssl-portal container without root privileges, following current best practices for container security.

## Current Architecture

```
Container (root)
└── Supervisor (root)
    ├── nginx (www-data)
    └── uWSGI (www-data)
        └── Flask (www-data)
            └── testssl.sh (www-data)
```

**Problem:** Supervisor runs as root to spawn child processes as www-data. This is a convenience, not a requirement.

## Target Architecture

```
Container (appuser, UID 1000)
└── entrypoint.sh
    ├── nginx
    └── uWSGI
        └── Flask
            └── testssl.sh
```

**Goal:** Everything runs as dedicated non-root user `appuser` (UID 1000). Compatible with:
- Rootless Docker
- Podman (rootless by default)
- Kubernetes with restricted Pod Security Standards
- OpenShift (random UID assignment)

---

## Implementation Plan

### Phase 1: Create dedicated user in Dockerfile

**File:** `Dockerfile`

Add user creation early in the build:

```dockerfile
# Create non-root user (UID 1000 for compatibility)
RUN useradd -r -u 1000 -g root -s /sbin/nologin appuser

# Create writable directories
RUN mkdir -p /tmp/nginx /tmp/testssl-scans \
    && chown -R appuser:root /tmp/nginx /tmp/testssl-scans \
    && chmod -R g+rwX /tmp/nginx /tmp/testssl-scans
```

**Why UID 1000?**
- Common default for first non-root user
- Works with most Kubernetes setups
- OpenShift can override with `runAsUser` in SecurityContext

**Why group `root`?**
- OpenShift runs containers with random UID but group `root` (GID 0)
- Setting group to `root` ensures files remain accessible

### Phase 2: Prepare nginx for non-root

**File:** `nginx.conf`

Changes needed:
- [ ] Remove `user www-data;` directive (process already runs as appuser)
- [ ] Change PID location to writable path
- [ ] Change temp paths to writable locations

```nginx
# Remove this line:
# user www-data;

# Writable paths (add at top):
pid /tmp/nginx/nginx.pid;
client_body_temp_path /tmp/nginx/client_body;
proxy_temp_path /tmp/nginx/proxy;
fastcgi_temp_path /tmp/nginx/fastcgi;
uwsgi_temp_path /tmp/nginx/uwsgi;
scgi_temp_path /tmp/nginx/scgi;

worker_processes 4;
daemon off;

events {
    worker_connections 768;
}

http {
    # ... rest unchanged ...
}
```

### Phase 3: Prepare uWSGI for non-root

**File:** `uwsgi.ini`

Changes needed:
- [ ] Remove `uid`, `gid`, `chown-socket` directives (already running as appuser)
- [ ] Socket location already in `/tmp` (good)

```ini
[uwsgi]
socket = /tmp/uwsgi.sock
# Remove these lines:
# uid = www-data
# gid = www-data
# chown-socket = www-data:www-data
chmod-socket = 666
processes = $(UWSGI_PROCESSES)
threads = $(UWSGI_THREADS)
# ... rest unchanged ...
```

### Phase 4: Create new entrypoint

**File:** `entrypoint.sh`

Replace supervisor with a simple process manager:

```bash
#!/bin/bash
set -e

export CHECKTIMEOUT=${TEST_TIMEOUT:-300}
UWSGI_READ_TIMEOUT=$((CHECKTIMEOUT + 10))

# Replace placeholder in nginx config
sed -i "s/@@UWSGI_READ_TIMEOUT@@/${UWSGI_READ_TIMEOUT}/" /etc/nginx/sites-enabled/default

# Trap signals for graceful shutdown
cleanup() {
    echo "Shutting down..."
    if [ -n "$UWSGI_PID" ]; then
        kill -TERM "$UWSGI_PID" 2>/dev/null || true
    fi
    if [ -n "$NGINX_PID" ]; then
        kill -QUIT "$NGINX_PID" 2>/dev/null || true
    fi
    wait
    exit 0
}
trap cleanup SIGTERM SIGINT SIGQUIT

# Start uWSGI in background
echo "Starting uWSGI..."
/usr/bin/uwsgi --ini /etc/uwsgi/uwsgi.ini &
UWSGI_PID=$!

# Wait for uWSGI socket
for i in $(seq 1 30); do
    if [ -S /tmp/uwsgi.sock ]; then
        break
    fi
    sleep 0.1
done

# Start nginx in background
echo "Starting nginx..."
/usr/sbin/nginx &
NGINX_PID=$!

echo "testssl-portal started (nginx PID: $NGINX_PID, uWSGI PID: $UWSGI_PID)"

# Wait for any process to exit
wait -n

# If we get here, one process died - exit with error
echo "Process exited unexpectedly"
exit 1
```

### Phase 5: Update Dockerfile

**File:** `Dockerfile`

Full changes:

```dockerfile
# ... builder stages unchanged ...

# ---- Final image ----
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

ARG BUILD_DATE
ARG VERSION
ARG TESTSSL_VERSION=v3.2.3
ENV TESTSSL_VERSION=${TESTSSL_REF}
ENV PORTAL_VERSION=${VERSION}

LABEL maintainer="hugobicho@gmail.com"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.version="${VERSION}"

ENV UWSGI_PROCESSES=4
ENV UWSGI_THREADS=2
ENV TEST_TIMEOUT=300
ENV TESTSSLDEBUG=0
ENV BRANDING_LABEL="TLS/SSL Server Checker"
ENV BRANDING_ICON_URL=""
ENV BRANDING_LINK=""
ENV DEFAULT_LOCALE=en

# Install packages (removed: supervisor)
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
        openssl net-tools dnsutils aha xxd python3-flask \
        bsdmainutils procps nginx-light uwsgi uwsgi-plugin-python3 socat \
        coreutils \
    && apt-get purge -y --auto-remove \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*

# Create non-root user (UID 1000, group root for OpenShift compatibility)
RUN useradd -r -u 1000 -g root -s /sbin/nologin appuser

# Create writable directories
RUN mkdir -p /tmp/nginx /tmp/testssl-scans \
    && chown -R appuser:root /tmp/nginx /tmp/testssl-scans /var/lib/nginx \
    && chmod -R g+rwX /tmp/nginx /tmp/testssl-scans /var/lib/nginx

# Copy configs (order matters for permissions)
COPY nginx.conf /etc/nginx/
COPY testssl.conf /etc/nginx/sites-enabled/default
COPY uwsgi.ini /etc/uwsgi/
COPY entrypoint.sh /

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

# Copy application files
COPY --from=testssl-builder /testssl.sh /testssl.sh
COPY --from=app-builder /app /testssl

# Ensure app directories are readable
RUN chown -R appuser:root /testssl /testssl.sh \
    && chmod -R g+rX /testssl /testssl.sh

WORKDIR /testssl
EXPOSE 5000

# Run as non-root user
USER 1000

ENTRYPOINT ["/entrypoint.sh"]
```

### Phase 6: Remove supervisor files

- [ ] Delete `supervisord.conf` from repository
- [ ] Remove from `.dockerignore` if referenced

### Phase 7: Update documentation

Files to update:
- [ ] `README.md` — Remove supervisor references, update security section
- [ ] `SECURITY.md` — Update Process Execution Users table (all as appuser), remove root references
- [ ] `CHANGELOG.md` — Add entry for rootless change
- [ ] `internal/DOCKER-README.md` — Update security note

**SECURITY.md Process Execution Users table (new):**

| Component | Execution User | Notes |
|-----------|----------------|-------|
| nginx | `appuser` (UID 1000) | Non-root, writable paths in /tmp |
| uWSGI | `appuser` (UID 1000) | Non-root |
| Flask app | `appuser` (UID 1000) | Runs under uWSGI |
| testssl.sh | `appuser` (UID 1000) | Spawned by Flask |

---

## Testing Checklist

### Basic functionality
- [ ] Container starts without errors
- [ ] Web UI accessible on port 5000
- [ ] Scan completes successfully
- [ ] Streaming output works
- [ ] STARTTLS scan works
- [ ] Language switching works
- [ ] Theme switching works

### Non-root verification
- [ ] `docker exec <container> id` shows UID 1000
- [ ] `docker exec <container> ps aux` shows no root processes
- [ ] No permission errors in logs

### Signal handling
- [ ] `docker stop` performs graceful shutdown
- [ ] Exit code is 0 on graceful stop
- [ ] Both nginx and uWSGI stop cleanly

### Compatibility testing
- [ ] Works with rootless Docker
- [ ] Works with Podman
- [ ] Works with `docker run --user 1000:1000`
- [ ] Works with `docker run --user 2000:0` (OpenShift simulation)

## Verification Commands

```bash
# Build new image
docker build -t testssl-portal:rootless .

# Test basic functionality
docker run --rm -p 5000:5000 testssl-portal:rootless

# Verify running user
docker exec <container> id
# Expected: uid=1000(appuser) gid=0(root)

# Verify no root processes
docker exec <container> ps aux
# Expected: all processes as appuser (UID 1000)

# Test with different UID (OpenShift simulation)
docker run --rm -p 5000:5000 --user 2000:0 testssl-portal:rootless

# Test graceful shutdown
timeout 10 docker run --rm -p 5000:5000 testssl-portal:rootless &
sleep 3
docker stop <container>
# Expected: clean shutdown, exit code 0

# Test with Podman
podman run --rm -p 5000:5000 testssl-portal:rootless
```

---

## Rollback Plan

If issues are found:
1. Revert Dockerfile changes
2. Restore supervisord.conf
3. Restore original nginx.conf, uwsgi.ini, entrypoint.sh
4. Remove USER directive

Keep the old files in a git branch (`pre-rootless`) for easy rollback.

---

## Benefits

| Benefit | Description |
|---------|-------------|
| **Security** | No root processes, reduced attack surface |
| **Compatibility** | Works with rootless Docker, Podman, Kubernetes, OpenShift |
| **Simplicity** | Fewer moving parts (no supervisor) |
| **Image size** | Slightly smaller (no supervisor package) |
| **Best practices** | Follows current container security trends |

## Risks and Mitigation

| Risk | Mitigation |
|------|------------|
| No automatic process restart | Use `restart: unless-stopped` in docker-compose |
| Shell script signal handling fragile | Tested trap handlers, clean shutdown |
| OpenShift random UID | Group `root` ensures file access |
| Debugging harder without supervisorctl | Use `docker logs`, `docker exec ps aux` |

---

## Files Changed Summary

| File | Action |
|------|--------|
| `Dockerfile` | Major changes: user creation, remove supervisor, add USER |
| `nginx.conf` | Update: remove user directive, add temp paths |
| `uwsgi.ini` | Update: remove uid/gid directives |
| `entrypoint.sh` | Rewrite: replace supervisor with process management |
| `supervisord.conf` | Delete |
| `README.md` | Update: remove supervisor references |
| `SECURITY.md` | Update: new process execution table |
| `CHANGELOG.md` | Add: rootless entry |
| `internal/DOCKER-README.md` | Update: security note |
