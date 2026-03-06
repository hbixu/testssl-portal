# Version Control

This document describes how versions are managed in the testssl-portal container image, including pinned component versions and how to verify them.

## Image Metadata

The image uses OCI labels and build arguments for version tracking:

| Build Argument | Description | Example |
|----------------|-------------|---------|
| `VERSION` | Image version tag | `1.0.0` |
| `BUILD_DATE` | Build timestamp (ISO 8601) | `2026-03-06T12:00:00Z` |
| `TESTSSL_REF` | testssl.sh branch or tag | `3.2` |

These are set as environment variables in the container:
- `PORTAL_VERSION` — Image version
- `TESTSSL_VERSION` — testssl.sh version

## Pinned Versions

The following components are pinned at build time for reproducibility:

| Component | Source | How Pinned |
|-----------|--------|------------|
| Base image | Docker Hub | `debian:bookworm-slim` tag |
| testssl.sh | GitHub | `TESTSSL_REF` build arg (branch/tag) |
| Python packages | Debian APT | `python3-flask` from bookworm repos |
| System packages | Debian APT | nginx-light, uwsgi, supervisor, aha, etc. |

**Benefits of pinned versions:**
- **Reproducibility** — Same build produces identical images
- **Stability** — No unexpected updates break functionality
- **Control** — Explicit version bumps through build args
- **Traceability** — Build metadata in OCI labels

## Version History

| Release | Base Image | testssl.sh | Notes |
|---------|------------|------------|-------|
| 1.0.0 | debian:bookworm-slim | 3.2 | Initial release |

## Application Versions

### testssl.sh

- **Source:** GitHub releases/branches
- **Repository:** [testssl/testssl.sh](https://github.com/testssl/testssl.sh)
- **Releases:** [GitHub Releases](https://github.com/testssl/testssl.sh/releases)
- **Default:** Branch `3.2` (stable)

Available versions:
- `3.2` — Stable branch (recommended)
- `v3.2.x` — Specific release tags (e.g., `v3.2.5`)
- `main` — Development branch (not recommended for production)

### Flask (python3-flask)

- **Source:** Debian APT (bookworm repository)
- **Package:** [python3-flask](https://packages.debian.org/bookworm/python3-flask)

### nginx

- **Source:** Debian APT (bookworm repository)
- **Package:** [nginx-light](https://packages.debian.org/bookworm/nginx-light)

### uWSGI

- **Source:** Debian APT (bookworm repository)
- **Package:** [uwsgi](https://packages.debian.org/bookworm/uwsgi)

### aha (ANSI to HTML)

- **Source:** Debian APT (bookworm repository)
- **Package:** [aha](https://packages.debian.org/bookworm/aha)
- **Repository:** [theZiz/aha](https://github.com/theZiz/aha)

## Current Versions

Default versions are defined in `build.sh`:

```bash
DEFAULT_VERSION="1.0.0"
DEFAULT_TESTSSL_REF="3.2"
```

The base image is defined in `Dockerfile`:

```dockerfile
FROM debian:bookworm-slim
```

## Base Image Version

| Property | Value |
|----------|-------|
| Image | `debian:bookworm-slim` |
| Repository | [Docker Hub](https://hub.docker.com/_/debian) |
| Tags | [Available Tags](https://hub.docker.com/_/debian/tags) |

**Important:**
- Do not use `latest` tag — always use a specific tag like `bookworm-slim`
- Debian releases have limited support windows; update base image periodically
- Security updates are applied when rebuilding the image

## How to Discover Available Versions

### Method 1: Automated Script

Use the version check scripts:

```bash
# Linux/macOS
./check-versions.sh

# Windows
.\check-versions.ps1
```

These scripts query the latest available versions for all components.

### Method 2: Direct Docker Command

```bash
# Check available package versions in Debian bookworm
docker run --rm debian:bookworm-slim apt-cache policy python3-flask nginx-light uwsgi aha
```

### Method 3: Package Repositories and Release Pages

| Component | Where to check |
|-----------|----------------|
| testssl.sh | [GitHub Releases](https://github.com/testssl/testssl.sh/releases) |
| Debian base image | [Docker Hub Tags](https://hub.docker.com/_/debian/tags) |
| python3-flask | [Debian Packages](https://packages.debian.org/bookworm/python3-flask) |
| nginx-light | [Debian Packages](https://packages.debian.org/bookworm/nginx-light) |

## Check Container Versions

```bash
# Check versions inside the container
docker exec testssl-portal printenv | grep VERSION

# Check Debian version
docker exec testssl-portal cat /etc/debian_version
```
