"""Pytest fixtures for the expert console E2E suite.

The fixtures boot the backend (uvicorn) and the Next.js production
build, then yield a Playwright `Page` for each test. We test against
the production build to validate that the bundle compiles and runs.

Skip the whole module if Playwright or its browsers aren't installed
(so CI without that toolchain doesn't see a hard fail).
"""

from __future__ import annotations

import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Iterator

import pytest

playwright = pytest.importorskip("playwright.sync_api")
sync_playwright = playwright.sync_playwright


HERE = Path(__file__).resolve().parent
# HERE = .../gym-anything/extras/research/expert_console/tests/e2e
EXPERT_DIR = HERE.parents[1]
ROOT = HERE.parents[4]  # gym-anything repo root
FRONTEND_DIR = EXPERT_DIR / "frontend"


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _wait_for(url: str, timeout: float) -> None:
    import urllib.request
    import urllib.error

    deadline = time.monotonic() + timeout
    last_err: Exception | None = None
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as resp:
                if 200 <= resp.status < 500:
                    return
        except Exception as exc:
            last_err = exc
        time.sleep(0.5)
    raise RuntimeError(f"Server at {url} did not become ready in {timeout}s: {last_err}")


@pytest.fixture(scope="session")
def stub_claude(tmp_path_factory: pytest.TempPathFactory) -> Path:
    bin_dir = tmp_path_factory.mktemp("claude-shim")
    claude = bin_dir / "claude"
    claude.write_text("#!/usr/bin/env bash\nexit 0\n")
    claude.chmod(0o755)
    return claude


@pytest.fixture(scope="session")
def sandbox_repo(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """A minimal sandbox copy of the repo so E2E tests don't mutate
    the real `extras/research/.../memory/expert_feedback.md` files.

    Mirrors only the paths the backend needs: `src/gym_anything` (just
    enough for the repo-root detector), `extras/research/...`, and
    `benchmarks/cua_world/environments/<env>` for envs we exercise.
    """
    sandbox = tmp_path_factory.mktemp("expert-console-repo")
    (sandbox / "src" / "gym_anything").mkdir(parents=True)
    (sandbox / "src" / "gym_anything" / "__init__.py").write_text("")
    shutil.copytree(
        ROOT / "extras" / "research" / "software_as_env",
        sandbox / "extras" / "research" / "software_as_env",
    )
    shutil.copytree(
        ROOT / "extras" / "research" / "task_generation",
        sandbox / "extras" / "research" / "task_generation",
    )
    envs_root = sandbox / "benchmarks" / "cua_world" / "environments"
    envs_root.mkdir(parents=True)
    for env_name in ("moodle_env",):
        src = ROOT / "benchmarks" / "cua_world" / "environments" / env_name
        shutil.copytree(src, envs_root / env_name)
    # Initialise as a git repo so the memory_diff service can run.
    subprocess.run(["git", "init", "-q"], cwd=str(sandbox), check=True)
    subprocess.run(
        ["git", "config", "user.email", "e2e@example.com"], cwd=str(sandbox), check=True
    )
    subprocess.run(
        ["git", "config", "user.name", "E2E"], cwd=str(sandbox), check=True
    )
    subprocess.run(["git", "add", "-A"], cwd=str(sandbox), check=True)
    subprocess.run(
        ["git", "commit", "-q", "-m", "sandbox init"], cwd=str(sandbox), check=True
    )
    return sandbox


@pytest.fixture(scope="session")
def backend_url(stub_claude: Path, sandbox_repo: Path) -> Iterator[str]:
    port = _free_port()
    env = os.environ.copy()
    env["OPENAI_API_KEY"] = env.get("OPENAI_API_KEY", "test-key")
    env["CLAUDE_BIN"] = str(stub_claude)
    env["EXPERT_CONSOLE_HOST"] = "127.0.0.1"
    env["EXPERT_CONSOLE_PORT"] = str(port)
    env["EXPERT_CONSOLE_REPO_ROOT"] = str(sandbox_repo)
    state_dir = sandbox_repo / "_state"
    state_dir.mkdir(parents=True, exist_ok=True)
    env["EXPERT_CONSOLE_STATE_DIR"] = str(state_dir)
    env["EXPERT_CONSOLE_DB_PATH"] = str(state_dir / "ec.sqlite3")
    env["EXPERT_CONSOLE_ARTIFACTS_DIR"] = str(state_dir / "runs")
    env["PATH"] = f"{stub_claude.parent}{os.pathsep}{env.get('PATH', '')}"
    log_path = Path("/tmp/expert_console_backend_e2e.log")
    log_path.write_text("")
    log_file = log_path.open("a")
    proc = subprocess.Popen(
        [sys.executable, "-m", "extras.research.expert_console.server.main"],
        cwd=str(ROOT),
        env=env,
        stdout=log_file,
        stderr=subprocess.STDOUT,
    )
    try:
        url = f"http://127.0.0.1:{port}"
        try:
            _wait_for(f"{url}/api/health", timeout=30)
        except RuntimeError as exc:
            log_file.flush()
            tail = log_path.read_text()[-4000:]
            raise RuntimeError(
                f"Backend never became ready. Tail of log:\n{tail}"
            ) from exc
        yield url
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        log_file.close()


@pytest.fixture(scope="session")
def frontend_url(backend_url: str) -> Iterator[str]:
    next_bin = FRONTEND_DIR / "node_modules" / ".bin" / "next"
    if not next_bin.is_file():
        pytest.skip(
            "frontend node_modules missing — run `npm install` in "
            f"{FRONTEND_DIR} before running E2E tests."
        )
    port = _free_port()
    env = os.environ.copy()
    env["EXPERT_CONSOLE_BACKEND"] = backend_url
    env["NODE_ENV"] = "production"

    # Next.js bakes `rewrites()` destinations into the routes-manifest
    # at build time. The backend URL is dynamic per test session, so
    # always rebuild with EXPERT_CONSOLE_BACKEND set; otherwise the
    # production server tries the stale default port.
    if (FRONTEND_DIR / ".next").exists():
        shutil.rmtree(FRONTEND_DIR / ".next")
    rc = subprocess.run(
        [str(next_bin), "build"],
        cwd=str(FRONTEND_DIR),
        env=env,
    ).returncode
    if rc != 0:
        pytest.fail(f"next build failed (rc={rc})")

    fe_log = Path("/tmp/expert_console_frontend_e2e.log")
    fe_log.write_text("")
    fe_log_file = fe_log.open("a")
    proc = subprocess.Popen(
        [str(next_bin), "start", "-p", str(port)],
        cwd=str(FRONTEND_DIR),
        env=env,
        stdout=fe_log_file,
        stderr=subprocess.STDOUT,
    )
    try:
        url = f"http://127.0.0.1:{port}"
        try:
            _wait_for(url, timeout=60)
        except RuntimeError as exc:
            fe_log_file.flush()
            tail = fe_log.read_text()[-4000:]
            raise RuntimeError(
                f"Frontend never became ready. Tail of log:\n{tail}"
            ) from exc
        yield url
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        fe_log_file.close()


@pytest.fixture
def page(frontend_url: str):
    with sync_playwright() as p:
        try:
            browser = p.chromium.launch(headless=True)
        except Exception as exc:
            pytest.skip(f"Chromium not available: {exc}")
        ctx = browser.new_context(viewport={"width": 1480, "height": 920})
        pg = ctx.new_page()
        pg.set_default_timeout(15_000)
        errors: list[str] = []
        pg.on("pageerror", lambda exc: errors.append(str(exc)))
        try:
            pg.goto(frontend_url)
            pg.wait_for_load_state("networkidle")
            yield pg
        finally:
            browser.close()
        for err in errors:
            print(f"[pageerror] {err}")
