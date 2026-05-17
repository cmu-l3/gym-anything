"""Launcher for the Gym-Anything Expert Console.

Invoked via:

    gym-anything-extras research expert_console launch

What it does:

1. Validates prerequisites (claude on PATH, OPENAI_API_KEY, frontend
   `node_modules`, frontend production build present or buildable).
2. Boots the FastAPI backend (uvicorn) on the configured port.
3. Boots the Next.js production server on the configured frontend
   port (with the backend URL baked into rewrites).
4. Optionally opens the browser to the frontend.
5. Forwards Ctrl+C to both subprocesses and tears them down on exit.

Subprocesses inherit stdout/stderr — logs go to the terminal where the
launcher runs. No log files. No silent backgrounding.

Fails loud if anything is missing.
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import webbrowser
from pathlib import Path
from typing import List, Optional


HERE = Path(__file__).resolve().parent
EXPERT_DIR = HERE.parent
FRONTEND_DIR = EXPERT_DIR / "frontend"
SERVER_MODULE = "extras.research.expert_console.server.main"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _repo_root() -> Path:
    """The gym-anything repo root (parent of `extras/`)."""
    extras_root = EXPERT_DIR
    while extras_root.name != "extras":
        if extras_root.parent == extras_root:
            raise RuntimeError("Could not locate the gym-anything repo root.")
        extras_root = extras_root.parent
    repo = extras_root.parent
    marker = repo / "src" / "gym_anything" / "__init__.py"
    if not marker.is_file():
        raise RuntimeError(
            f"Expected gym-anything marker at {marker}; got {repo} as root."
        )
    return repo


def _port_is_free(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind((host, port))
            return True
        except OSError:
            return False


def _wait_for(url: str, *, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    last_err: Exception | None = None
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as resp:
                if 200 <= resp.status < 500:
                    return
        except (urllib.error.URLError, OSError) as exc:
            last_err = exc
        time.sleep(0.5)
    raise RuntimeError(f"{url} did not become ready in {timeout}s: {last_err}")


def _resolve_npm() -> Path:
    candidate = shutil.which("npm")
    if not candidate:
        raise RuntimeError(
            "`npm` not found on PATH. Install Node.js >= 20 to run the "
            "expert console frontend."
        )
    return Path(candidate)


def _next_bin() -> Path:
    candidate = FRONTEND_DIR / "node_modules" / ".bin" / "next"
    if not candidate.is_file():
        raise RuntimeError(
            f"frontend/node_modules is missing. Run:\n  cd {FRONTEND_DIR} && npm install"
        )
    return candidate


# ---------------------------------------------------------------------------
# Frontend build
# ---------------------------------------------------------------------------


_FRONTEND_SOURCE_ROOTS = ("app", "components", "lib")
_FRONTEND_SOURCE_FILES = (
    "package.json",
    "next.config.mjs",
    "tailwind.config.ts",
    "postcss.config.mjs",
    "tsconfig.json",
)


def _newest_source_mtime() -> float:
    """Walk the frontend source tree and return the latest mtime.

    Used to detect "source code changed since last build" — otherwise the
    launcher would happily serve a stale bundle that omits new features.
    """
    newest = 0.0
    for name in _FRONTEND_SOURCE_FILES:
        path = FRONTEND_DIR / name
        if path.is_file():
            newest = max(newest, path.stat().st_mtime)
    for root in _FRONTEND_SOURCE_ROOTS:
        root_path = FRONTEND_DIR / root
        if not root_path.is_dir():
            continue
        for path in root_path.rglob("*"):
            if not path.is_file():
                continue
            # Skip emacs / vim swap detritus.
            if path.name.startswith(".") or path.name.endswith("~"):
                continue
            newest = max(newest, path.stat().st_mtime)
    return newest


def _frontend_needs_build(backend_url: str) -> bool:
    """Re-build the frontend whenever any of these is true:

      * `.next/BUILD_ID` missing (no prior build)
      * `.expert-console-backend` marker missing
      * the marker URL doesn't match the requested backend URL
        (Next.js bakes `rewrites()` destinations at build time)
      * any frontend source file is newer than the build (covers the
        common "I edited a component but the bundle is stale" trap)
    """
    build_id = FRONTEND_DIR / ".next" / "BUILD_ID"
    marker = FRONTEND_DIR / ".next" / ".expert-console-backend"
    if not build_id.is_file():
        return True
    if not marker.is_file():
        return True
    try:
        if marker.read_text(encoding="utf-8").strip() != backend_url:
            return True
    except OSError:
        return True
    build_mtime = build_id.stat().st_mtime
    if _newest_source_mtime() > build_mtime:
        return True
    return False


def _build_frontend(backend_url: str) -> None:
    next_bin = _next_bin()
    env = os.environ.copy()
    env["EXPERT_CONSOLE_BACKEND"] = backend_url
    env["NODE_ENV"] = "production"
    print(f"[launch] Building Next.js bundle (backend={backend_url})…")
    rc = subprocess.run(
        [str(next_bin), "build"],
        cwd=str(FRONTEND_DIR),
        env=env,
    ).returncode
    if rc != 0:
        raise RuntimeError(f"`next build` failed with exit code {rc}")
    marker = FRONTEND_DIR / ".next" / ".expert-console-backend"
    marker.write_text(backend_url, encoding="utf-8")


# ---------------------------------------------------------------------------
# Backend / frontend supervisors
# ---------------------------------------------------------------------------


def _start_backend(host: str, port: int) -> subprocess.Popen:
    repo_root = _repo_root()
    env = os.environ.copy()
    env["EXPERT_CONSOLE_HOST"] = host
    env["EXPERT_CONSOLE_PORT"] = str(port)
    print(f"[launch] Starting backend on http://{host}:{port}")
    return subprocess.Popen(
        [sys.executable, "-m", SERVER_MODULE],
        cwd=str(repo_root),
        env=env,
        stdin=subprocess.DEVNULL,
    )


def _start_frontend(host: str, port: int, backend_url: str) -> subprocess.Popen:
    next_bin = _next_bin()
    env = os.environ.copy()
    env["EXPERT_CONSOLE_BACKEND"] = backend_url
    env["NODE_ENV"] = "production"
    print(f"[launch] Starting frontend on http://{host}:{port}")
    return subprocess.Popen(
        [str(next_bin), "start", "-H", host, "-p", str(port)],
        cwd=str(FRONTEND_DIR),
        env=env,
        stdin=subprocess.DEVNULL,
    )


def _wait_for_or_die(name: str, url: str, timeout: float, proc: subprocess.Popen) -> None:
    try:
        _wait_for(url, timeout=timeout)
    except RuntimeError as exc:
        rc = proc.poll()
        if rc is None:
            proc.terminate()
        raise RuntimeError(
            f"{name} never became ready: {exc}. exit={rc}."
        ) from exc


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gym-anything-extras research expert_console launch",
        description="Boot the FastAPI backend and the Next.js frontend.",
    )
    p.add_argument("--backend-host", default="127.0.0.1")
    p.add_argument("--backend-port", type=int, default=8765)
    p.add_argument("--frontend-host", default="127.0.0.1")
    p.add_argument("--frontend-port", type=int, default=3456)
    p.add_argument(
        "--no-open",
        action="store_true",
        help="Do not open the browser after both servers are up.",
    )
    p.add_argument(
        "--rebuild",
        action="store_true",
        help="Always re-run `next build` even when the existing build matches.",
    )
    p.add_argument(
        "--build-only",
        action="store_true",
        help="Run `next build` (against the configured backend URL) and exit.",
    )
    return p


def run(argv: Optional[List[str]] = None) -> int:
    args = _build_parser().parse_args(argv or [])

    # ------------------------------------------------------------------
    # Up-front validation. Fail loud if any of these are missing —
    # better to refuse to start than to half-start and confuse the user.
    # ------------------------------------------------------------------
    if not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError(
            "OPENAI_API_KEY is not set. The expert console uses GPT-5.4 "
            "for artifact summarization. Export the key and rerun."
        )
    if not shutil.which("claude") and not os.environ.get("CLAUDE_BIN"):
        raise RuntimeError(
            "`claude` CLI is not on PATH and CLAUDE_BIN is not set. "
            "Install Claude Code (https://docs.claude.com/en/docs/claude-code) "
            "before launching the console."
        )
    _resolve_npm()  # raises if missing
    _next_bin()  # raises if node_modules missing

    if not _port_is_free(args.backend_host, args.backend_port):
        raise RuntimeError(
            f"Backend port {args.backend_host}:{args.backend_port} is in use. "
            f"Pass --backend-port to choose another."
        )
    if not _port_is_free(args.frontend_host, args.frontend_port):
        raise RuntimeError(
            f"Frontend port {args.frontend_host}:{args.frontend_port} is in use. "
            f"Pass --frontend-port to choose another."
        )

    backend_url = f"http://{args.backend_host}:{args.backend_port}"
    frontend_url = f"http://{args.frontend_host}:{args.frontend_port}"

    if args.rebuild or _frontend_needs_build(backend_url):
        _build_frontend(backend_url)
    else:
        print(f"[launch] Reusing existing Next.js build (backend={backend_url}).")

    if args.build_only:
        print("[launch] --build-only set; not starting servers.")
        return 0

    backend = _start_backend(args.backend_host, args.backend_port)
    frontend: subprocess.Popen | None = None
    try:
        _wait_for_or_die(
            "backend", f"{backend_url}/api/health", timeout=20, proc=backend
        )
        frontend = _start_frontend(
            args.frontend_host, args.frontend_port, backend_url
        )
        _wait_for_or_die("frontend", frontend_url, timeout=30, proc=frontend)

        print()
        print(f"[launch] Expert Console ready: {frontend_url}")
        print(f"[launch] Backend health:       {backend_url}/api/health")
        print(f"[launch] Backend docs:         {backend_url}/api/docs")
        print("[launch] Ctrl+C to stop.")
        print()

        if not args.no_open:
            try:
                webbrowser.open(frontend_url)
            except Exception:
                pass

        # Block until either subprocess exits, or the user hits Ctrl+C.
        try:
            while True:
                if backend.poll() is not None:
                    raise RuntimeError(
                        f"Backend exited unexpectedly with code {backend.returncode}."
                    )
                if frontend.poll() is not None:
                    raise RuntimeError(
                        f"Frontend exited unexpectedly with code {frontend.returncode}."
                    )
                time.sleep(0.5)
        except KeyboardInterrupt:
            print("\n[launch] Stopping (Ctrl+C)…")
    finally:
        for name, proc in (("frontend", frontend), ("backend", backend)):
            if proc is None:
                continue
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
            print(f"[launch] {name} exited ({proc.returncode}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(run(sys.argv[1:]))
