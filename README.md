# testssl-portal

Web portal to check servers' TLS/SSL configuration using [testssl.sh](https://github.com/testssl/testssl.sh). The UI supports multiple languages (en, pt-PT), configurable branding, and dark/light themes. Results are streamed in real-time as the scan progresses.

## Features

- ✅ Web-based interface for [testssl.sh](https://github.com/testssl/testssl.sh) TLS/SSL scanning
- ✅ Real-time streaming output with ANSI color rendering via [aha](https://github.com/theZiz/aha)
- ✅ Internationalization (i18n) support — English (en) and Portuguese (pt-PT) included
- ✅ Customizable branding (logo, label, link)
- ✅ Dark/light theme toggle with persistent preference
- ✅ Multiple scan types: certificate only, normal (IDS-friendly), full
- ✅ STARTTLS support for SMTP, IMAP, POP3, FTP, and other protocols
- ✅ Multi-platform images: `linux/amd64` and `linux/arm64`
- ✅ Based on [debian:bookworm-slim](https://hub.docker.com/_/debian)

## Requirements

- Docker 20.10+ (or Docker Desktop)
- Docker Compose v2 (optional, for compose-based deployment)
- No special capabilities or devices required
- No host kernel requirements

## File Structure

```
testssl-portal/
├── Dockerfile              # Multi-stage build: testssl.sh + Flask webfrontend
├── docker-compose.yml      # Docker Compose example
├── build.sh                # Helper script for building images
├── check-versions.sh       # Check for component updates (Linux/macOS)
├── check-versions.ps1      # Check for component updates (Windows PowerShell)
├── entrypoint.sh           # Container entrypoint (sets timeouts)
├── supervisord.conf        # Process supervisor config (nginx + uWSGI)
├── nginx.conf              # Nginx main configuration
├── testssl.conf            # Nginx site config (upstream uWSGI)
├── uwsgi.ini               # uWSGI app server configuration
├── webfrontend/            # Flask application
│   ├── SSLTestPortal.py    # Main Flask app
│   ├── templates/          # Jinja2 HTML templates
│   ├── static/             # CSS, JS, favicon
│   └── locales/            # i18n translation files (*.json)
├── VERSIONS.md             # Version control and component versions
├── SECURITY.md             # Security and process execution details
└── CHANGELOG.md            # Change history
```

## Build the Image

See [VERSIONS.md](VERSIONS.md) for available versions and how to check component versions.

### Option 1: Helper Script (Recommended)

```bash
chmod +x build.sh
./build.sh --help   # See all options

# Local build (native platform)
./build.sh

# Build with specific testssl.sh version
./build.sh --version 1.0.0 --testssl-version v3.2.5

# Multi-platform build and push to Docker Hub
docker login
./build.sh --version 1.0.0 --testssl-version 3.2 --registry docker.io/username --platform linux/amd64,linux/arm64 --push
```

### Option 2: Direct Docker Build (Single Platform)

```bash
docker build \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  --build-arg VERSION=1.0.0 \
  --build-arg TESTSSL_VERSION=3.2 \
  -t testssl-portal:1.0.0 \
  .
```

### Option 3: Multi-Platform Build with Push

```bash
# Create buildx builder (if not already created)
docker buildx create --name multiplatform --use

# Login to registry before push
docker login

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  --build-arg VERSION=1.0.0 \
  --build-arg TESTSSL_VERSION=3.2 \
  --tag username/testssl-portal:1.0.0 \
  --tag username/testssl-portal:latest \
  --push \
  .
```

## Configuration

### Environment Variables

All environment variables are **optional**. Set them only to override the defaults.

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `UWSGI_PROCESSES` | No | Number of uWSGI worker processes (max parallel scans) | `4` |
| `UWSGI_THREADS` | No | Threads per uWSGI process | `2` |
| `TEST_TIMEOUT` | No | Scan timeout in seconds | `300` |
| `TESTSSLDEBUG` | No | testssl.sh debug level (0–6) | `0` |
| `BRANDING_LABEL` | No | Portal name shown in the header | `TLS/SSL Server Checker` |
| `BRANDING_ICON_URL` | No | URL of the logo/icon (empty = default lock icon) | — |
| `BRANDING_LINK` | No | URL when clicking the branding (empty = `/`) | — |
| `DEFAULT_LOCALE` | No | Default UI language (`en`, `pt-PT`) | `en` |
| `ENABLED_LOCALES` | No | Comma-separated list of enabled locales (e.g. `en,pt-PT` or `en`) | all available |

### Build Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `VERSION` | Image version tag | `1.0.0` |
| `BUILD_DATE` | Build timestamp (ISO 8601) | auto-generated |
| `BASEIMAGE_VERSION` | Debian base image tag | `bookworm-slim` |
| `TESTSSL_VERSION` | testssl.sh branch or tag to clone | `3.2` |

### Quick Start

```bash
# Build
docker build -t testssl-portal .

# Run with defaults
docker run --rm -p 5000:5000 testssl-portal

# Run with custom branding and locale
docker run --rm -p 5000:5000 \
  -e BRANDING_LABEL="My SSL Portal" \
  -e DEFAULT_LOCALE=en \
  testssl-portal
```

### Docker Compose

A ready-to-use `docker-compose.yml` is included in the repository:

```bash
docker compose up -d
```

See `docker-compose.yml` for configuration options.

## Usage

### Access the Web UI

Open [http://localhost:5000](http://localhost:5000) in your browser.

### Scan Types

- **Certificate Only** — Quick scan of server certificate and chain
- **Normal (IDS-friendly)** — Standard scan with IDS-friendly timing
- **Full** — Complete testssl.sh scan (all checks)

### STARTTLS Support

Enable STARTTLS for protocols like SMTP, IMAP, POP3, FTP, XMPP, etc. Select the protocol from the dropdown when STARTTLS is enabled.

### Check Container Status

```bash
# View logs
docker logs testssl-portal

# Check running processes
docker exec testssl-portal ps aux
```

## How It Works

1. **Initialization** — The entrypoint script sets `CHECKTIMEOUT` from `TEST_TIMEOUT` and configures nginx read timeout accordingly.

2. **Process Management** — Supervisor starts and monitors two services:
   - **nginx** — Reverse proxy on port 5000, serves static files and proxies to uWSGI
   - **uWSGI** — Runs the Flask application with configured workers and threads

3. **Scan Request** — When a user submits a scan:
   - Form validation (host, port, scan type)
   - Preflight TCP connection check
   - testssl.sh execution with output piped through `aha` for ANSI-to-HTML conversion

4. **Streaming Output** — Results are streamed in real-time via Server-Sent Events (SSE) or polling fallback, allowing users to see progress as the scan runs.

5. **Graceful Shutdown** — On SIGTERM, supervisor sends QUIT to nginx and gracefully terminates uWSGI workers.

## Troubleshooting

### Connection Failed Error

If you see "Connection failed" before the scan starts:

1. Check if the port is correct (default 443 for HTTPS)
2. For internal hosts, ensure the container can resolve and reach them
3. Verify there are no firewall rules blocking outbound connections

### Scan Timeout

If scans timeout before completing:

1. Increase the timeout:
   ```bash
   docker run -e TEST_TIMEOUT=600 -p 5000:5000 testssl-portal
   ```

2. Use a lighter scan type (Certificate Only) for slow targets

### Streaming Output Not Updating

If the output appears all at once instead of streaming:

1. Check if you're behind a buffering reverse proxy
2. Disable proxy buffering (see [Behind a Reverse Proxy](#behind-a-reverse-proxy))

### Language Not Changing

1. Clear browser cookies for the site
2. Verify the locale file exists in `webfrontend/locales/`
3. Check `ENABLED_LOCALES` if set

## Behind a Reverse Proxy

When running behind a reverse proxy (e.g., nginx, Traefik), disable buffering to ensure streaming output works:

```nginx
location / {
    proxy_pass       http://localhost:5000;
    proxy_set_header Host       $host;
    proxy_set_header X-Real-IP  $remote_addr;
    proxy_buffering  off;
}
```

## Security

The container runs multiple processes with different users for security. See [SECURITY.md](SECURITY.md) for detailed information about:

- Process execution users (root, www-data)
- Service architecture
- Input validation and host blocking

**Summary:**
- Supervisor runs as root (required for process management)
- nginx and uWSGI run as `www-data` (non-root)
- Input validation blocks localhost and private IP scans
- No special capabilities or privileges required

## License

This project is licensed under the GNU General Public License v3.0. See the [LICENSE](LICENSE) file for details.

## Credits

- [testssl.sh](https://github.com/testssl/testssl.sh) — TLS/SSL testing tool (Dirk Wetter and contributors)
- [aha](https://github.com/theZiz/aha) — ANSI to HTML converter
- [Flask](https://flask.palletsprojects.com/) — Python web framework
