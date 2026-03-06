# Security

This document describes the security model of testssl-portal, including process execution users, input validation, and network considerations.

## Network Security

### No Special Network Requirements

testssl-portal does not require special network capabilities or privileges:

- No `NET_ADMIN` capability needed
- No `/dev/net/tun` device required
- No VPN or proxy tunneling involved
- Standard outbound HTTPS/TLS connections only

### Input Validation

The application validates all user input before executing scans:

1. **Host validation** — Hostname or IP address format check via regex
2. **Port validation** — Must be a valid port number (0–65535)
3. **Blocked hosts** — The following are blocked to prevent internal scanning:
   - `localhost`
   - `127.*` (IPv4 loopback)
   - `::1` (IPv6 loopback)

4. **Confirmation required** — Users must explicitly confirm before scanning

### Preflight Connection Check

Before executing testssl.sh, the application performs a TCP preflight check to verify the target is reachable. This prevents wasting resources on unreachable hosts.

## User Permissions

### Process Execution Users

The container runs multiple processes with different users for security isolation:

| Component | Execution User | Notes |
|-----------|----------------|-------|
| Supervisor | `root` | Required to manage child processes and handle signals |
| nginx | `www-data` | Configured in `nginx.conf` via `user` directive |
| uWSGI | `www-data` | Configured in `uwsgi.ini` via `uid`/`gid` |
| Flask app | `www-data` | Runs under uWSGI worker processes |
| testssl.sh | `www-data` | Spawned by Flask as subprocess |

### Why Root for Supervisor

Supervisor runs as root because:

1. It needs to start nginx and uWSGI with proper user context
2. It must handle process signals (SIGTERM, SIGHUP) correctly
3. It manages the process lifecycle and restarts

However, supervisor does **not** expose any network services directly.

### Why www-data for Services

All network-facing services run as `www-data`:

- **nginx** — Listens on port 5000, proxies to uWSGI
- **uWSGI** — Runs Flask application workers
- **Flask** — Handles HTTP requests, spawns testssl.sh

This follows the principle of least privilege for services handling user input.

## No PUID/PGID Support

This container does not implement PUID/PGID (user/group ID mapping) because:

1. No persistent data volumes that require specific ownership
2. All services run as the standard `www-data` user
3. Temporary scan data is stored in `/tmp` (container-local)

If you need to run as a specific user, use Docker's `--user` flag:

```bash
docker run --user 1000:1000 -p 5000:5000 testssl-portal
```

Note: Running as a non-root user may prevent supervisor from functioning correctly.

## File Ownership

| Path | Owner | Purpose |
|------|-------|---------|
| `/testssl/` | `root` | Flask application files (read-only) |
| `/testssl.sh/` | `root` | testssl.sh installation (read-only) |
| `/tmp/testssl-scans/` | `www-data` | Temporary scan output (created at runtime) |
| `/tmp/uwsgi.sock` | `www-data` | uWSGI socket (created at runtime) |

## Service Architecture

```
                    ┌─────────────────────────────────────────┐
                    │            Container (root)             │
                    │                                         │
                    │  ┌─────────────────────────────────┐   │
                    │  │     Supervisor (root)           │   │
                    │  │                                 │   │
                    │  │   ┌──────────┐   ┌──────────┐  │   │
                    │  │   │  nginx   │   │  uWSGI   │  │   │
                    │  │   │(www-data)│   │(www-data)│  │   │
                    │  │   └────┬─────┘   └────┬─────┘  │   │
                    │  │        │              │        │   │
                    │  └────────┼──────────────┼────────┘   │
                    │           │   Unix Socket│            │
   Port 5000 ◄──────┼───────────┘              │            │
                    │                          ▼            │
                    │                    ┌──────────┐       │
                    │                    │  Flask   │       │
                    │                    │(www-data)│       │
                    │                    └────┬─────┘       │
                    │                         │             │
                    │                         ▼             │
                    │                   ┌───────────┐       │
                    │                   │testssl.sh │       │
                    │                   │(www-data) │       │
                    │                   └───────────┘       │
                    │                         │             │
                    │                         ▼             │
                    │               External TLS Servers    │
                    └─────────────────────────────────────────┘
```

## Recommendations

### Production Deployment

1. **Run behind a reverse proxy** — Use nginx, Traefik, or similar with TLS termination
2. **Restrict access** — Use authentication or firewall rules to limit who can scan
3. **Monitor usage** — Scans consume resources; monitor for abuse
4. **Set appropriate timeouts** — Adjust `TEST_TIMEOUT` based on expected scan targets

### Network Isolation

If deploying in a sensitive environment:

1. Use Docker networks to isolate the container
2. Consider using `--network=host` only if necessary (not recommended)
3. Use firewall rules to restrict outbound connections if needed

### Logging

Logs are written to stdout/stderr and can be collected via Docker logging drivers:

```bash
docker logs testssl-portal
docker logs -f testssl-portal  # Follow logs
```
