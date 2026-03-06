# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-06

### Added

- Initial release of testssl-portal
- Web-based interface for testssl.sh TLS/SSL scanning
- Real-time streaming output with ANSI color rendering via aha
- Internationalization (i18n) support with Portuguese (pt-PT) and English (en) locales
- Customizable branding (logo, label, link) via environment variables
- Dark/light theme toggle with cookie-based persistence
- Multiple scan types: certificate only, normal (IDS-friendly), full
- STARTTLS support for SMTP, IMAP, POP3, FTP, XMPP, and other protocols
- Async scan architecture with SSE streaming and polling fallback
- Multi-platform Docker images (linux/amd64, linux/arm64)
- Helper build script (`build.sh`) with multi-platform support
- nginx reverse proxy with uWSGI backend
- Supervisor for process management
- Input validation blocking localhost and private IP scans
- Configurable timeout and concurrency via environment variables

---

## Types of Changes

- **Added** — New features
- **Changed** — Changes to existing functionality
- **Deprecated** — Features that will be removed in future versions
- **Removed** — Features that have been removed
- **Fixed** — Bug fixes
- **Security** — Vulnerability fixes
