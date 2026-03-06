# testssl-portal

Web portal to check servers’ TLS/SSL configuration using [testssl.sh](https://github.com/testssl/testssl.sh). The UI supports multiple languages (e.g. pt-PT, en), configurable branding, and dark/light theme.

## Quick start

```bash
docker build -t testssl-portal .
docker run --rm -p 5000:5000 --name testssl-portal testssl-portal
```

Open [http://localhost:5000](http://localhost:5000)

### Docker Compose

Example `docker-compose.yml`:

```yaml
services:
  testssl-portal:
    ports:
      - "5000:5000"
    # Optional: override defaults
    environment:
      - DEFAULT_LOCALE=pt-PT
      # - BRANDING_LABEL=My SSL Portal
      # - TEST_TIMEOUT=300
```

Run with:

```bash
docker compose up -d
```

## Build the image

### Option 1: Helper script (Recommended)

```bash
chmod +x build.sh
./build.sh --help   # See all options

# Build for linux/amd64 and linux/arm64 and push to Docker Hub repository
VERSION=1.0.0 TESTSSL_REF=3.2 ./build.sh --push --registry docker.io/username
```

### Option 2: Direct Docker build (single platform)

```bash
docker build \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  --build-arg VERSION=1.0.0 \
  --build-arg TESTSSL_REF=3.2 \
  -t testssl-portal:1.0.0 \
  .
```

### Option 2b: Multi-platform build (amd64 + arm64)

```bash
# Create and use a buildx builder (if not already created)
docker buildx create --name multiplatform --use

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  --build-arg VERSION=1.0.0 \
  --build-arg TESTSSL_REF=3.2 \
  --tag username/testssl-portal:1.0.0 \
  --tag username/testssl-portal:latest \
  --push \
  .
# Pushes both tags to Docker Hub (requires: docker login)
```

Replace `username` with your Docker Hub username.

Build args: `TESTSSL_REF` is the [testssl/testssl.sh](https://github.com/testssl/testssl.sh) branch or tag (e.g. `3.2`, `v3.2.5`).

## Configuration (environment variables)

All environment variables are **optional**. They only need to be set when you want to override the defaults below.

### Concurrency and timeout


| Variable          | Description                                                                                        | Default |
| ----------------- | -------------------------------------------------------------------------------------------------- | ------- |
| `UWSGI_PROCESSES` | Number of uWSGI processes (max parallel scans).                                                    | `4`     |
| `UWSGI_THREADS`   | Threads per process.                                                                               | `2`     |
| `TEST_TIMEOUT`    | Scan timeout in seconds. The entrypoint sets `CHECKTIMEOUT` from this so the app and nginx use it. | `300`   |
| `TESTSSLDEBUG`    | testssl.sh debug level (0–6).                                                                      | `0`     |


### Branding and locale

**Available locales** (from `webfrontend/locales/*.json`): `pt-PT` (Português), `en` (English). To add more, see `webfrontend/locales/README.md`.


| Variable            | Description                                                                                                                                                                                                      | Default                  |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `BRANDING_LABEL`    | Portal name in the header.                                                                                                                                                                                       | `TLS/SSL Server Checker` |
| `BRANDING_ICON_URL` | URL of the logo/icon (empty = default lock icon).                                                                                                                                                                | —                        |
| `BRANDING_LINK`     | URL when clicking the branding (empty = `/`).                                                                                                                                                                    | —                        |
| `DEFAULT_LOCALE`    | Default UI language (must be one of the enabled locales).                                                                                                                                                        | `pt-PT`                  |
| `ENABLED_LOCALES`   | Comma-separated list of locale codes to show in the selector (e.g. `pt-PT,en` or `en`). Only codes that have a `.json` file in `webfrontend/locales/` are accepted. If unset, all available locales are enabled. | all available            |


Example:

```bash
docker run --rm -p 5000:5000 \
  -e BRANDING_LABEL="My SSL Portal" \
  -e BRANDING_ICON_URL="/static/logo.svg" \
  -e DEFAULT_LOCALE=en \
  testssl-portal
```

## Behind a reverse proxy (e.g. Nginx)

Disable `proxy_buffering` so streaming output is visible during the scan:

```nginx
location / {
    proxy_pass       http://localhost:5000;
    proxy_set_header Host       $host;
    proxy_set_header X-Real-IP   $remote_addr;
    proxy_buffering  off;
}
```

## Project structure

- **webfrontend/** — Flask app (templates, static assets, locales). Copied into the image at build time.
- **Dockerfile** — Builds testssl.sh from the chosen ref and the webfrontend from the repo; no clone of an external webfrontend.

## Credits

- [testssl.sh](https://github.com/testssl/testssl.sh) — TLS/SSL testing script (Dirk Wetter and contributors).
- This portal uses Flask, nginx, uWSGI, and [aha](https://github.com/theZiz/aha) for ANSI-to-HTML output.

## License

See [LICENSE](LICENSE) in this repository.