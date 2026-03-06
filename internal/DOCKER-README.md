# testssl-portal

Web portal for TLS/SSL server testing using testssl.sh. Features real-time streaming output, internationalization (en, pt-PT), customizable branding, and dark/light themes.

[![Source](https://img.shields.io/badge/Source-GitHub-blue)](https://github.com/YOUR_USERNAME/testssl-portal)
[![Platforms](https://img.shields.io/badge/Platforms-amd64%20%7C%20arm64-lightgrey)](https://hub.docker.com/r/YOUR_USERNAME/testssl-portal)

## Features

- ✅ Web-based interface for [testssl.sh](https://github.com/testssl/testssl.sh)
- ✅ Real-time streaming output via [aha](https://github.com/theZiz/aha)
- ✅ Internationalization (en, pt-PT)
- ✅ Customizable branding and dark/light themes
- ✅ STARTTLS support for multiple protocols
- ✅ Based on [debian:bookworm-slim](https://hub.docker.com/_/debian)

## Image Versions

| Image Tag | Base Image | testssl.sh |
|-----------|------------|------------|
| `1.0.0` | debian:bookworm-20250224-slim | v3.2.3 |

## Requirements

- Docker 20.10+
- No special capabilities or devices required

## Quick Start

```bash
# Pull the image
docker pull YOUR_USERNAME/testssl-portal:1.0.0

# Run the container
docker run -d -p 5000:5000 --name testssl-portal YOUR_USERNAME/testssl-portal:1.0.0
```

Open [http://localhost:5000](http://localhost:5000)

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `UWSGI_PROCESSES` | No | Worker processes (default: 4) |
| `UWSGI_THREADS` | No | Threads per process (default: 2) |
| `TEST_TIMEOUT` | No | Scan timeout in seconds (default: 300) |
| `BRANDING_LABEL` | No | Portal name in header |
| `BRANDING_ICON_URL` | No | URL of logo/icon in header |
| `BRANDING_LINK` | No | URL when clicking the branding |
| `DEFAULT_LOCALE` | No | UI language: `en` (default), `pt-PT` |

See [GitHub repository](https://github.com/YOUR_USERNAME/testssl-portal) for full environment variable list.

## Example docker-compose

```yaml
services:
  testssl-portal:
    image: YOUR_USERNAME/testssl-portal:1.0.0
    ports:
      - "5000:5000"
    environment:
      - DEFAULT_LOCALE=en
      - BRANDING_LABEL=My SSL Portal
    restart: unless-stopped
```

## Ports

| Port | Service |
|------|---------|
| 5000 | Web UI (HTTP) |

## Security

- Supervisor runs as root (process management)
- nginx and uWSGI run as `www-data` (non-root)

See repository for full security documentation.

## Links

- **Source:** [GitHub](https://github.com/YOUR_USERNAME/testssl-portal)
- **Issues:** [GitHub Issues](https://github.com/YOUR_USERNAME/testssl-portal/issues)
- **License:** [GPL-3.0](https://github.com/YOUR_USERNAME/testssl-portal/blob/main/LICENSE)
