# -*- coding: utf-8 -*-
"""
TLS/SSL Server Checker — Flask webfrontend for testssl.sh.
Supports i18n (pt-PT, en), branding via env, dark/light theme.
"""
import json
import os
import re
import shlex
import signal
import socket
import subprocess
import tempfile
import threading
import time
import uuid
from pathlib import Path

from markupsafe import escape
from flask import Flask, request, render_template, flash, redirect, url_for, Response, stream_with_context, jsonify

application = app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "change-me-in-production")

# Paths
BASE = Path(__file__).resolve().parent
TESTSSL_DIR = Path("/testssl.sh")
TESTSSL_CMD = TESTSSL_DIR / "testssl.sh"
CHANGELOG = TESTSSL_DIR / "testssl-changelog.txt"
LOCALES_DIR = BASE / "locales"

# Env
CHECKTIMEOUT = int(os.environ.get("CHECKTIMEOUT", "300"))
PREFLIGHT_TIMEOUT = 10
_default_scan_store = Path(tempfile.gettempdir()) / "testssl-scans"
SCAN_STORE_DIR = Path(os.environ.get("SCAN_STORE_DIR", str(_default_scan_store)))

# Locales: available = all *.json in locales/; supported = from ENABLED_LOCALES or all available
def _available_locale_codes():
    return sorted(p.stem for p in LOCALES_DIR.glob("*.json") if p.is_file())

_AVAILABLE_LOCALES = _available_locale_codes()

_env_enabled = os.environ.get("ENABLED_LOCALES", "").strip()
if _env_enabled:
    _parsed = [x.strip() for x in _env_enabled.split(",") if x.strip() and x.strip() in _AVAILABLE_LOCALES]
    SUPPORTED_LOCALES = tuple(_parsed) if _parsed else tuple(_AVAILABLE_LOCALES)
else:
    SUPPORTED_LOCALES = tuple(_AVAILABLE_LOCALES)

_default = (os.environ.get("DEFAULT_LOCALE", "") or "pt-PT").strip()
DEFAULT_LOCALE = _default if _default in SUPPORTED_LOCALES else (SUPPORTED_LOCALES[0] if SUPPORTED_LOCALES else "en")

# Host validation: hostname or IP, block localhost/private
HOST_RE = re.compile(
    r"^(?:(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?|"
    r"(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))$",
    re.IGNORECASE,
)
BLOCKED_HOSTS = ("localhost", "127.", "::1")


def strip_ansi(text):
    """Remove ANSI escape sequences (e.g. from testssl.sh --version output)."""
    if not text:
        return text
    return re.sub(r"\x1b\[[0-9;]*m", "", text)


# Extract short version line from testssl.sh --version output (e.g. "testssl.sh 3.2.3")
TESTSSL_VERSION_RE = re.compile(
    r"testssl\.sh\s+version\s+([\d.]+)",
    re.IGNORECASE,
)


def parse_testssl_version(raw_output):
    """Return a short string like 'testssl.sh 3.2.3' from raw --version output, or None."""
    if not raw_output:
        return None
    cleaned = strip_ansi(raw_output)
    match = TESTSSL_VERSION_RE.search(cleaned)
    if match:
        return f"testssl.sh {match.group(1)}"
    return None


def get_locale():
    """Determine locale from query, cookie, or Accept-Language."""
    lang = request.args.get("lang") or request.cookies.get("lang")
    if lang in SUPPORTED_LOCALES:
        return lang
    if request.accept_languages:
        best = request.accept_languages.best_match([x for x in SUPPORTED_LOCALES])
        if best:
            return best
    return DEFAULT_LOCALE


# Cookie names and max age for preferences (1 year); both locale and theme stored in cookies
LANG_COOKIE_NAME = "lang"
THEME_COOKIE_NAME = "theme"
PREFS_COOKIE_MAX_AGE = 365 * 24 * 3600


def get_theme():
    """Theme from cookie (dark/light); default dark."""
    theme = request.cookies.get(THEME_COOKIE_NAME, "dark").strip().lower()
    return theme if theme in ("dark", "light") else "dark"


@app.after_request
def set_lang_cookie(response):
    """Persist locale in a cookie when user selects language via ?lang=."""
    lang = request.args.get("lang")
    if lang in SUPPORTED_LOCALES:
        response.set_cookie(
            LANG_COOKIE_NAME,
            lang,
            max_age=PREFS_COOKIE_MAX_AGE,
            path="/",
            samesite="Lax",
        )
    return response


def load_translations(lang):
    path = LOCALES_DIR / f"{lang}.json"
    if not path.is_file():
        path = LOCALES_DIR / "en.json"
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def get_locale_display_names():
    """List of (locale_code, display_name) for the language selector; name from each locale's meta.name."""
    result = []
    for code in SUPPORTED_LOCALES:
        t = load_translations(code)
        name = (t.get("meta") or {}).get("name", code)
        result.append((code, name))
    return result


def get_branding():
    return {
        "label": os.environ.get("BRANDING_LABEL", "").strip(),
        "icon_url": os.environ.get("BRANDING_ICON_URL", "").strip(),
        "link": os.environ.get("BRANDING_LINK", "").strip(),
    }


def template_ctx():
    locale = get_locale()
    t = load_translations(locale)
    # Flatten for templates: t.common.appName -> t['common']['appName']
    def get(key, default=""):
        try:
            parts = key.split(".")
            v = t
            for p in parts:
                v = v.get(p, default if p == parts[-1] else {})
            return v if isinstance(v, str) else default
        except Exception:
            return default

    branding = get_branding()
    if not branding["label"] and t:
        branding["label"] = t.get("common", {}).get("appName", "TLS/SSL Server Checker")
    return {
        "t": t,
        "get": get,
        "locale": locale,
        "theme": get_theme(),
        "supported_locales": SUPPORTED_LOCALES,
        "locale_options": get_locale_display_names(),
        "branding": branding,
    }


def preflight_tcp(host, port):
    """Try TCP connect to (host, port). Return True if connected."""
    try:
        sock = socket.create_connection((host, int(port)), timeout=PREFLIGHT_TIMEOUT)
        sock.close()
        return True
    except Exception:
        return False


def validate_form(host, port, scantype, starttls, protocol, confirm):
    """Return (True, None) or (False, error_message_key)."""
    if not host or not HOST_RE.match(host.strip()):
        return False, "wrongHost"
    h = host.strip().lower()
    if h == "localhost" or h.startswith("127.") or h == "::1":
        return False, "wrongHost"
    try:
        p = int(port)
        if p < 0 or p > 65535:
            return False, "wrongPort"
    except (TypeError, ValueError):
        return False, "wrongPort"
    if scantype not in ("certonly", "normal", "full"):
        scantype = "normal"
    if starttls and not protocol:
        protocol = "smtp"
    if not confirm or (isinstance(confirm, str) and confirm.lower() != "yes"):
        return False, "confirmRequired"
    return True, None


def build_testssl_args(host, port, scantype, starttls, protocol):
    """Build argv for testssl.sh (without script path)."""
    args = ["--quiet", "--debug=0"]
    if scantype == "certonly":
        args.append("--server-defaults")
    elif scantype == "normal":
        args.append("--ids-friendly")
    # else full: no extra
    if starttls and protocol:
        args.extend(["-t", protocol, f"{host}:{port}"])
    else:
        args.append(f"{host}:{port}")
    return args


# Async scan: file-based store so any worker can serve /result/<id> and /result/<id>/stream.
def _scan_dir(scan_id):
    """Path to scan directory (shared across workers)."""
    return SCAN_STORE_DIR / scan_id


def _get_scan_meta(scan_id):
    """Return {"target": str, "done": bool} or None if scan not found."""
    d = _scan_dir(scan_id)
    meta_path = d / "meta.json"
    if not meta_path.is_file():
        return None
    try:
        with open(meta_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _write_scan_chunk(output_path, chunk):
    """Append a string chunk to the scan output file."""
    with open(output_path, "a", encoding="utf-8") as f:
        f.write(chunk)
        f.flush()


def _set_scan_done(scan_id):
    """Mark scan as done in meta.json."""
    meta_path = _scan_dir(scan_id) / "meta.json"
    try:
        with open(meta_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
        meta["done"] = True
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump(meta, f)
    except Exception:
        pass


def _run_pipeline_in_pty(testssl_cmd_list, env, output_path, timeout_seconds):
    """Run testssl | aha in a pseudo-TTY so both programs line-buffer; write chunks to output_path.
    Returns True if completed normally, False if killed by timeout. Unix only; returns None if pty unavailable.
    No setsid() so it works in Docker (seccomp often blocks it); on timeout we kill the shell and the
    PTY slave closes, so the pipeline gets SIGHUP and exits."""
    try:
        import pty
    except ImportError:
        return None
    pipeline = "exec " + " ".join(shlex.quote(c) for c in testssl_cmd_list) + " 2>&1 | aha --black --no-header"
    env = dict(env)
    env["TERM"] = "xterm-256color"

    pid, master_fd = pty.fork()
    if pid == 0:
        os.chdir(str(TESTSSL_DIR))
        os.execve("/bin/sh", ["sh", "-c", pipeline], env)
        os._exit(127)
    timed_out = threading.Event()

    def kill_on_timeout():
        timed_out.set()
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass

    timer = threading.Timer(timeout_seconds, kill_on_timeout)
    timer.start()
    try:
        while True:
            try:
                data = os.read(master_fd, 256)
            except OSError:
                break
            if not data:
                break
            _write_scan_chunk(output_path, data.decode("utf-8", errors="replace"))
        try:
            os.waitpid(pid, 0)
        except OSError:
            pass
    finally:
        timer.cancel()
        try:
            os.close(master_fd)
        except OSError:
            pass
    return not timed_out.is_set()


def _run_scan_background(scan_id, host, port, scantype, starttls, protocol, locale, theme, index_url, output_path):
    """Run preflight + testssl in background; append HTML chunks to output_path and set done in meta."""
    try:
        t = load_translations(locale)
        running_txt = t.get("result", {}).get("statusRunning", "Running…")
        _write_scan_chunk(output_path, f'<p class="line-info">{escape(running_txt)}</p>')
        if not preflight_tcp(host, port):
            err_msg = t.get("errors", {}).get("connectionFailed", "Connection failed.")
            _write_scan_chunk(output_path, f'<p class="line-err">{escape(err_msg)}</p>')
            _set_scan_done(scan_id)
            return
        cmd = [str(TESTSSL_CMD)] + build_testssl_args(host, port, scantype, starttls, protocol)
        env = os.environ.copy()

        # Prefer PTY: testssl | aha run in a pseudo-TTY so both line-buffer and output is incremental.
        pty_result = _run_pipeline_in_pty(cmd, env, output_path, CHECKTIMEOUT)
        if pty_result is not None:
            if not pty_result:
                _write_scan_chunk(
                    output_path,
                    '<p class="line-err">' + escape(t.get("errors", {}).get("timeout", "Scan timeout.")) + "</p>",
                )
            return

        # Fallback (e.g. Windows): pipe + stdbuf -oL on aha so output is line-buffered.
        timed_out = threading.Event()
        proc = None

        def kill_after_timeout():
            timed_out.set()
            if proc is not None:
                try:
                    proc.kill()
                except OSError:
                    pass

        try:
            proc = subprocess.Popen(
                cmd,
                cwd=str(TESTSSL_DIR),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                env=env,
                universal_newlines=False,
            )
            timer = threading.Timer(CHECKTIMEOUT, kill_after_timeout)
            timer.start()
            try:
                aha_cmd = ["stdbuf", "-oL", "aha", "--black", "--no-header"]
                try:
                    aha = subprocess.Popen(
                        aha_cmd,
                        stdin=proc.stdout,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                    )
                except FileNotFoundError:
                    aha = subprocess.Popen(
                        ["aha", "--black", "--no-header"],
                        stdin=proc.stdout,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                    )
                proc.stdout.close()
                for chunk in iter(lambda: aha.stdout.read(256), b""):
                    _write_scan_chunk(output_path, chunk.decode("utf-8", errors="replace"))
                aha.wait()
                proc.wait()
            finally:
                timer.cancel()
            if timed_out.is_set():
                _write_scan_chunk(
                    output_path,
                    '<p class="line-err">' + escape(t.get("errors", {}).get("timeout", "Scan timeout.")) + "</p>",
                )
        except Exception as e:
            _write_scan_chunk(output_path, f"<p class=\"line-err\">Error: {escape(str(e))}</p>")
    finally:
        _set_scan_done(scan_id)


def _sse_message(typ, data=None):
    """One SSE message event (default type) with JSON payload for broad client compatibility."""
    payload = {"t": typ}
    if data is not None:
        payload["d"] = data
    return "data: " + json.dumps(payload, ensure_ascii=False) + "\n\n"


@app.route("/")
def index():
    ctx = template_ctx()
    return render_template("main.html", **ctx)


@app.route("/scan", methods=["POST"])
def start_scan():
    """Start scan asynchronously; return scan id. Frontend redirects to /result/<id> and subscribes to SSE."""
    ctx = template_ctx()
    host = request.form.get("host", "").strip()
    port = request.form.get("port", "443")
    scantype = request.form.get("scantype", "normal")
    starttls = request.form.get("starttls") == "yes"
    protocol = request.form.get("protocol", "smtp").strip() or "smtp"
    confirm = request.form.get("confirm")

    ok, err_key = validate_form(host, port, scantype, starttls, protocol, confirm)
    if not ok:
        t = ctx["t"]
        err_msg = t.get("errors", {}).get(err_key, err_key)
        return jsonify({"error": err_msg}), 400

    scan_id = str(uuid.uuid4())
    target = f"{host}:{port}"
    scan_path = _scan_dir(scan_id)
    scan_path.mkdir(parents=True, exist_ok=True)
    output_path = scan_path / "output"
    with open(scan_path / "meta.json", "w", encoding="utf-8") as f:
        json.dump({"target": target, "done": False}, f)
    output_path.touch()
    thread = threading.Thread(
        target=_run_scan_background,
        args=(
            scan_id,
            host,
            port,
            scantype,
            starttls,
            protocol,
            ctx["locale"],
            ctx["theme"],
            request.url_root.rstrip("/") + url_for("index"),
            output_path,
        ),
        daemon=True,
    )
    thread.start()
    return jsonify({"id": scan_id}), 202


@app.route("/result/<scan_id>")
def result_page(scan_id):
    """Result page for async scan; uses tail polling by default for progressive output."""
    meta = _get_scan_meta(scan_id)
    if not meta:
        return render_template("result_not_found.html", **template_ctx()), 404
    ctx = template_ctx()
    ctx["scan_id"] = scan_id
    ctx["target"] = meta["target"]
    ctx["use_top_links"] = False
    return render_template("result_async.html", **ctx)


def _tail_safe_start(content, start_at):
    """Return index of first safe boundary (after '>' or '\\n') at or after start_at, or start_at."""
    if start_at <= 0:
        return 0
    search = content[: start_at + 1]
    last = max(
        search.rfind(">"),
        search.rfind("\n"),
    )
    return (last + 1) if last >= 0 else 0


@app.route("/result/<scan_id>/tail")
def result_tail(scan_id):
    """Return new output since byte offset (for polling when SSE is buffered). GET ?since=<bytes>."""
    meta = _get_scan_meta(scan_id)
    if not meta:
        return jsonify({"error": "Not found"}), 404
    output_path = _scan_dir(scan_id) / "output"
    try:
        since = int(request.args.get("since", 0))
    except (TypeError, ValueError):
        since = 0
    if since < 0:
        since = 0
    data = ""
    size = 0
    start = 0
    if output_path.is_file():
        try:
            with open(output_path, "r", encoding="utf-8", errors="replace") as f:
                raw = f.read()
                size = len(raw)
                start = _tail_safe_start(raw, min(since, size))
                data = raw[start:]
        except Exception:
            pass
    return jsonify({"data": data, "size": size, "start": start, "done": bool(meta.get("done"))})


@app.route("/result/<scan_id>/stream")
def result_stream(scan_id):
    """SSE stream of scan output (HTML chunks). Reads from file so any worker can serve."""
    _stream_debug_t0 = time.monotonic()
    app.logger.info("[stream-debug] request_received scan_id=%s at %.3f", scan_id, _stream_debug_t0)
    meta = _get_scan_meta(scan_id)
    if not meta:
        return jsonify({"error": "Not found"}), 404
    output_path = _scan_dir(scan_id) / "output"

    _CHUNK_SEND_SIZE = 512
    _CHUNK_SAFE_AFTER = (">", "\n")  # split after these to avoid cutting inside HTML tags (e.g. color="white">)

    def _chunk_safe(content):
        """Yield content in chunks that end at > or newline so insertAdjacentHTML never gets mid-tag."""
        pos = 0
        while pos < len(content):
            end = min(pos + _CHUNK_SEND_SIZE, len(content))
            if end < len(content):
                search = content[pos:end]
                last_safe = -1
                for safe in _CHUNK_SAFE_AFTER:
                    i = search.rfind(safe)
                    if i != -1 and i > last_safe:
                        last_safe = i
                if last_safe != -1:
                    end = pos + last_safe + 1
            yield content[pos:end]
            pos = end

    def generate():
        # Send something immediately so the response starts and proxies/servers flush (avoids multi-second buffering)
        app.logger.info("[stream-debug] first_yield_open at %.3f (+%.3f s from request)", time.monotonic(), time.monotonic() - _stream_debug_t0)
        yield ": open\n\n"
        last_size = 0
        poll_interval = 0.03  # 30ms so first output (e.g. "Start...") appears quickly
        chunk_yield_pause = 0.015  # brief pause every few chunks so browser can paint
        chunks_before_pause = 2
        first_read_logged = False
        first_chunk_yield_logged = False
        while True:
            try:
                if output_path.is_file():
                    with open(output_path, "r", encoding="utf-8", errors="replace") as f:
                        f.seek(last_size)
                        new_content = f.read()
                        if new_content:
                            if not first_read_logged:
                                app.logger.info(
                                    "[stream-debug] first_file_read_with_content at %.3f (+%.3f s from request)",
                                    time.monotonic(),
                                    time.monotonic() - _stream_debug_t0,
                                )
                                first_read_logged = True
                            last_size = f.tell()
                            n = 0
                            for chunk in _chunk_safe(new_content):
                                if not first_chunk_yield_logged:
                                    app.logger.info(
                                        "[stream-debug] first_chunk_yield at %.3f (+%.3f s from request)",
                                        time.monotonic(),
                                        time.monotonic() - _stream_debug_t0,
                                    )
                                    first_chunk_yield_logged = True
                                yield _sse_message("chunk", chunk)
                                n += 1
                                if n % chunks_before_pause == 0:
                                    time.sleep(chunk_yield_pause)
            except Exception:
                pass
            meta = _get_scan_meta(scan_id)
            if meta and meta.get("done"):
                try:
                    with open(output_path, "r", encoding="utf-8", errors="replace") as f:
                        f.seek(last_size)
                        tail = f.read()
                        if tail:
                            n = 0
                            for chunk in _chunk_safe(tail):
                                if not first_chunk_yield_logged:
                                    app.logger.info(
                                        "[stream-debug] first_chunk_yield at %.3f (+%.3f s from request)",
                                        time.monotonic(),
                                        time.monotonic() - _stream_debug_t0,
                                    )
                                    first_chunk_yield_logged = True
                                yield _sse_message("chunk", chunk)
                                n += 1
                                if n % chunks_before_pause == 0:
                                    time.sleep(chunk_yield_pause)
                except Exception:
                    pass
                break
            time.sleep(poll_interval)
        yield _sse_message("done")

    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-store",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


@app.route("/", methods=["POST"])
def run_scan():
    ctx = template_ctx()
    host = request.form.get("host", "").strip()
    port = request.form.get("port", "443")
    scantype = request.form.get("scantype", "normal")
    starttls = request.form.get("starttls") == "yes"
    protocol = request.form.get("protocol", "smtp").strip() or "smtp"
    confirm = request.form.get("confirm")

    ok, err_key = validate_form(host, port, scantype, starttls, protocol, confirm)
    if not ok:
        t = ctx["t"]
        err_msg = t.get("errors", {}).get(err_key, err_key)
        flash(err_msg, "error")
        return render_template("main.html", **ctx), 400

    # Stream response so the result page appears immediately and output streams as it runs.
    # For progressive display the form must submit to an iframe (target="result-frame");
    # a top-level form POST causes many browsers to buffer the whole response before painting.
    _CHUNK_SIZE = 512  # small yields so first paint and progress stream flush sooner

    def generate():
        # Part 1: top of result page — yield in small chunks so iframe gets content immediately
        first_chunk = render_template(
            "result_start.html",
            target=f"{host}:{port}",
            use_top_links=True,
            **ctx,
        ).encode("utf-8")
        for i in range(0, len(first_chunk), _CHUNK_SIZE):
            yield first_chunk[i : i + _CHUNK_SIZE]
        # Part 2: preflight TCP (after first paint); on failure stream error and end
        if not preflight_tcp(host, port):
            t = ctx["t"]
            err_msg = t.get("errors", {}).get("connectionFailed", "Connection failed.")
            yield f'<p class="line-err">{escape(err_msg)}</p>'.encode("utf-8")
            yield render_template("result_end.html", **ctx).encode("utf-8")
            return
        # Part 3: run testssl.sh and pipe through aha
        cmd = [str(TESTSSL_CMD)] + build_testssl_args(host, port, scantype, starttls, protocol)
        env = os.environ.copy()
        env["TERM"] = "xterm-256color"
        timed_out = threading.Event()

        def kill_after_timeout():
            timed_out.set()
            try:
                proc.kill()
            except OSError:
                pass

        try:
            proc = subprocess.Popen(
                cmd,
                cwd=str(TESTSSL_DIR),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                env=env,
                universal_newlines=False,
            )
            timer = threading.Timer(CHECKTIMEOUT, kill_after_timeout)
            timer.start()
            try:
                aha = subprocess.Popen(
                    ["aha", "--black", "--no-header"],
                    stdin=proc.stdout,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                )
                proc.stdout.close()
                for chunk in iter(lambda: aha.stdout.read(256), b""):
                    yield chunk
                aha.wait()
                proc.wait()
            finally:
                timer.cancel()
            if timed_out.is_set():
                yield b"<p class=\"line-err\">Scan timeout.</p>"
        except Exception as e:
            yield f"<p class=\"line-err\">Error: {e!s}</p>".encode("utf-8")
        # Part 3: close result body and show "done" bar
        yield render_template("result_end.html", **ctx).encode("utf-8")

    return Response(
        stream_with_context(generate()),
        mimetype="text/html; charset=utf-8",
        headers={
            "Cache-Control": "no-store",
            "X-Accel-Buffering": "no",  # nginx: disable buffering for streaming
        },
    )


# testssl version: use TESTSSL_VERSION from image build (set in Dockerfile from TESTSSL_VERSION ARG); fallback to subprocess only when not in Docker
_testssl_version_cache = None


def get_testssl_version():
    """Version fixed at image build (TESTSSL_VERSION ARG); no subprocess in Docker."""
    env_version = os.environ.get("TESTSSL_VERSION", "").strip()
    if env_version:
        return f"testssl.sh {env_version}"
    global _testssl_version_cache
    if _testssl_version_cache is not None:
        return _testssl_version_cache
    version = "—"
    if TESTSSL_CMD.exists():
        try:
            out = subprocess.run(
                [str(TESTSSL_CMD), "--version"],
                capture_output=True,
                text=True,
                timeout=5,
                cwd=str(TESTSSL_DIR),
            )
            raw = (out.stdout or out.stderr or "").strip()
            version = parse_testssl_version(raw) or (strip_ansi(raw).split("\n")[0][:80] if raw else "—")
        except Exception:
            pass
    _testssl_version_cache = version
    return version


def get_portal_version():
    """Portal version from image build (build-arg VERSION) or env PORTAL_VERSION."""
    v = (os.environ.get("PORTAL_VERSION") or "").strip()
    return v if v else "—"


@app.route("/about/")
def about():
    ctx = template_ctx()
    ctx["testssl_version"] = get_testssl_version()
    ctx["portal_version"] = get_portal_version()
    return render_template("about.html", **ctx)
