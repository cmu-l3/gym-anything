#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import atexit
import hmac
import json
import mimetypes
import os
import re
import secrets
import signal
import socket
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import webbrowser
from collections import deque
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import quote, unquote, urlparse
from urllib.request import urlopen


DASHBOARD_ROOT = Path(__file__).resolve().parent
STATIC_ROOT = DASHBOARD_ROOT / "static"
sys.path.insert(0, str(DASHBOARD_ROOT))

try:  # Package import in tests; local import when executed as a script.
    from .catalog import BENCHMARK_ROOT, REPO_ROOT, build_catalog, environment_index
    from .reviews import EnvironmentReviewStore
except ImportError:  # pragma: no cover - exercised by the script entrypoint.
    from catalog import BENCHMARK_ROOT, REPO_ROOT, build_catalog, environment_index  # type: ignore[no-redef]
    from reviews import EnvironmentReviewStore  # type: ignore[no-redef]


EVENT_PREFIX = "__CAPTCHA_HUB_EVENT__"
ANSI_ESCAPE = re.compile(r"(?:\x1B[@-_][0-?]*[ -/]*[@-~])|(?:\x1B\][^\x07]*(?:\x07|\x1B\\))")
SAFE_AGENT = re.compile(r"^[A-Za-z][A-Za-z0-9_]{1,80}$")
SAFE_MODEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_./:+-]{0,180}$")
SAFE_EXPERIMENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,100}$")
RUNNERS = {"avf", "qemu", "qemu_native", "docker", "local"}
BROWSER_APP_ROOT = BENCHMARK_ROOT / "shared_runtime" / "app"
BROWSER_SERVER = BENCHMARK_ROOT / "shared_runtime" / "server" / "weird_captcha_server.py"
BROWSER_SETUP = BENCHMARK_ROOT / "shared_scripts" / "setup_task.py"
DEFAULT_TOKEN_PATH = Path(
    os.environ.get("CAPTCHA_BENCH_COMPANION_TOKEN_PATH", Path.home() / ".captcha-bench" / "companion-token")
).expanduser().resolve()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def clean_log(line: str) -> str:
    return ANSI_ESCAPE.sub("", line).replace("\r", "").strip()


def load_or_create_companion_token(path: Path = DEFAULT_TOKEN_PATH) -> str:
    try:
        existing = path.read_text(encoding="utf-8").strip()
    except OSError:
        existing = ""
    if len(existing) >= 24:
        return existing
    token = secrets.token_urlsafe(32)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(token + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    temporary.replace(path)
    return token


def is_loopback_host(host: str) -> bool:
    if host.lower() == "localhost":
        return True
    try:
        return socket.getaddrinfo(host, None)[0][4][0] in {"127.0.0.1", "::1"}
    except socket.gaierror:
        return False


def reserve_local_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def process_env(runner: str) -> dict[str, str]:
    env = os.environ.copy()
    python_paths = [str(REPO_ROOT / "src"), str(REPO_ROOT)]
    if env.get("PYTHONPATH"):
        python_paths.append(env["PYTHONPATH"])
    env["PYTHONPATH"] = os.pathsep.join(python_paths)
    env["GYM_ANYTHING_RUNNER"] = runner
    env.setdefault("PYTHONUNBUFFERED", "1")
    env.setdefault("TERM", "dumb")
    return env


def available_agents() -> list[str]:
    source = REPO_ROOT / "agents" / "agents" / "__init__.py"
    try:
        tree = ast.parse(source.read_text(encoding="utf-8"))
        for node in tree.body:
            if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "__all__" for target in node.targets):
                return [str(item.value) for item in node.value.elts if isinstance(item, ast.Constant) and isinstance(item.value, str)]
    except (OSError, SyntaxError, AttributeError):
        pass
    return ["ClaudeAgent", "GeminiComputerUseAgent", "Qwen3VLAgent"]


def open_vnc_viewer(port: int, password: str = "password") -> tuple[bool, str]:
    address = f"localhost::{port}"
    if sys.platform == "darwin":
        tiger_apps = sorted(Path("/Applications").glob("TigerVNC Viewer*.app"), reverse=True)
        if tiger_apps:
            subprocess.Popen(
                ["open", "-n", str(tiger_apps[0]), "--args", "-Shared", "-SecurityTypes", "VncAuth", address],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return True, f"Opened TigerVNC at {address} (password: {password})"
        subprocess.Popen(["open", f"vnc://localhost:{port}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True, f"Opened the system VNC viewer at localhost:{port}"
    try:
        opener = "xdg-open" if sys.platform.startswith("linux") else "open"
        subprocess.Popen([opener, f"vnc://localhost:{port}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True, f"Opened VNC at localhost:{port}"
    except OSError as exc:
        return False, str(exc)


class SessionManager:
    def __init__(self, runner: str, max_active: int = 2) -> None:
        self.runner = runner
        self.max_active = max_active
        self._jobs: dict[str, dict[str, Any]] = {}
        self._lock = threading.RLock()

    def list(self) -> list[dict[str, Any]]:
        with self._lock:
            return [self._snapshot(job) for job in sorted(self._jobs.values(), key=lambda item: item["created_ts"], reverse=True)]

    def get(self, job_id: str) -> dict[str, Any] | None:
        with self._lock:
            job = self._jobs.get(job_id)
            return self._snapshot(job) if job else None

    def start(self, environment_id: str, task_id: str, *, seed: int, auto_open: bool) -> dict[str, Any]:
        catalog = environment_index()
        environment = catalog.get(environment_id)
        if environment is None:
            raise ValueError("unknown environment")
        if task_id not in {task["id"] for task in environment["tasks"]}:
            raise ValueError("unknown task")
        with self._lock:
            active = [job for job in self._jobs.values() if job["status"] in {"queued", "booting", "running", "stopping"}]
            if len(active) >= self.max_active:
                raise RuntimeError(f"at most {self.max_active} live environments may run at once")
            duplicate = next((job for job in active if job["environment_id"] == environment_id), None)
            if duplicate:
                raise RuntimeError("this environment already has a live session")

            job_id = uuid.uuid4().hex[:10]
            command = [
                sys.executable,
                "-u",
                str(DASHBOARD_ROOT / "session_worker.py"),
                "--env-dir",
                str(REPO_ROOT / environment["environment_path"]),
                "--task",
                task_id,
                "--runner",
                self.runner,
                "--seed",
                str(seed),
            ]
            job: dict[str, Any] = {
                "id": job_id,
                "kind": "vnc",
                "environment_id": environment_id,
                "mechanic_id": environment["mechanic_id"],
                "title": environment["title"],
                "task_id": task_id,
                "seed": seed,
                "runner": self.runner,
                "status": "queued",
                "phase_message": "Queued for launch",
                "created_at": utc_now(),
                "created_ts": time.time(),
                "ready_at": None,
                "stopped_at": None,
                "session": None,
                "logs": deque(maxlen=180),
                "auto_open": auto_open,
                "viewer_opened": False,
                "command": command,
                "process": None,
            }
            self._jobs[job_id] = job
            process = subprocess.Popen(
                command,
                cwd=REPO_ROOT,
                env=process_env(self.runner),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                start_new_session=True,
            )
            job["process"] = process
            job["status"] = "booting"
            job["phase_message"] = "Booting virtual environment"
            threading.Thread(target=self._read_worker, args=(job_id,), daemon=True).start()
            return self._snapshot(job)

    def start_browser(self, environment_id: str, task_id: str, *, seed: int, auto_open: bool) -> dict[str, Any]:
        catalog = environment_index()
        environment = catalog.get(environment_id)
        if environment is None or environment.get("stage") != "built":
            raise ValueError("unknown or non-runnable environment")
        if task_id not in {task["id"] for task in environment["tasks"]}:
            raise ValueError("unknown task")
        task_json = REPO_ROOT / environment["environment_path"] / "tasks" / task_id / "task.json"
        if not task_json.is_file():
            raise ValueError("task definition is missing")

        with self._lock:
            active = [job for job in self._jobs.values() if job["status"] in {"queued", "booting", "running", "stopping"}]
            if len(active) >= self.max_active:
                raise RuntimeError(f"at most {self.max_active} live environments may run at once")
            if any(job["environment_id"] == environment_id for job in active):
                raise RuntimeError("this environment already has a live session")

            job_id = uuid.uuid4().hex[:10]
            state_dir = Path(tempfile.mkdtemp(prefix=f"captcha-bench-{job_id}-"))
            port = reserve_local_port()
            command = [
                sys.executable,
                "-B",
                str(BROWSER_SERVER),
                "--host",
                "127.0.0.1",
                "--port",
                str(port),
                "--app-dir",
                str(BROWSER_APP_ROOT),
                "--state-dir",
                str(state_dir),
            ]
            job = {
                "id": job_id,
                "kind": "browser",
                "environment_id": environment_id,
                "mechanic_id": environment["mechanic_id"],
                "title": environment["title"],
                "task_id": task_id,
                "task_json": str(task_json),
                "seed": seed,
                "runner": "local browser",
                "status": "queued",
                "phase_message": "Preparing a fresh local challenge",
                "created_at": utc_now(),
                "created_ts": time.time(),
                "ready_at": None,
                "stopped_at": None,
                "session": {"browser_url": f"http://127.0.0.1:{port}/", "browser_port": port},
                "logs": deque(maxlen=180),
                "auto_open": auto_open,
                "viewer_opened": False,
                "command": command,
                "process": None,
                "state_dir": str(state_dir),
            }
            self._jobs[job_id] = job
            threading.Thread(target=self._boot_browser, args=(job_id,), daemon=True).start()
            return self._snapshot(job)

    def _boot_browser(self, job_id: str) -> None:
        with self._lock:
            job = self._jobs[job_id]
            task_json = str(job["task_json"])
            state_dir = str(job["state_dir"])
            seed = int(job["seed"])
            command = list(job["command"])
            browser_url = str(job["session"]["browser_url"])
            job["status"] = "booting"
            job["phase_message"] = "Generating local challenge"
        setup = subprocess.run(
            [
                sys.executable,
                "-B",
                str(BROWSER_SETUP),
                "--task-json",
                task_json,
                "--state-dir",
                state_dir,
                "--seed",
                str(seed),
            ],
            cwd=REPO_ROOT,
            env=process_env(self.runner),
            capture_output=True,
            text=True,
        )
        with self._lock:
            canceled = self._jobs[job_id]["status"] in {"stopping", "stopped"}
        if canceled:
            self._remove_browser_state(job_id)
            return
        if setup.returncode != 0:
            detail = clean_log(setup.stderr or setup.stdout or "challenge setup failed")
            with self._lock:
                job = self._jobs[job_id]
                job["status"] = "failed"
                job["phase_message"] = "Could not generate the local challenge"
                job["logs"].append(detail[-1200:])
            self._remove_browser_state(job_id)
            return

        try:
            process = subprocess.Popen(
                command,
                cwd=REPO_ROOT,
                env=process_env(self.runner),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                start_new_session=True,
            )
        except OSError as exc:
            with self._lock:
                job = self._jobs[job_id]
                job["status"] = "failed"
                job["phase_message"] = "Could not start the local puzzle server"
                job["logs"].append(str(exc))
            self._remove_browser_state(job_id)
            return

        with self._lock:
            job = self._jobs[job_id]
            job["process"] = process
            canceled = job["status"] in {"stopping", "stopped"}
            if not canceled:
                job["phase_message"] = "Starting local browser runtime"
        threading.Thread(target=self._read_browser_server, args=(job_id,), daemon=True).start()
        if canceled:
            try:
                os.killpg(process.pid, signal.SIGINT)
            except ProcessLookupError:
                pass
            return

        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and process.poll() is None:
            try:
                with urlopen(f"{browser_url}health", timeout=0.35) as response:
                    if response.status == HTTPStatus.OK:
                        with self._lock:
                            job = self._jobs[job_id]
                            canceled = job["status"] in {"stopping", "stopped"}
                            if not canceled:
                                job["status"] = "running"
                                job["phase_message"] = "Local browser puzzle is ready"
                                job["ready_at"] = utc_now()
                        if canceled:
                            try:
                                os.killpg(process.pid, signal.SIGINT)
                            except ProcessLookupError:
                                pass
                            return
                        if bool(job.get("auto_open")):
                            try:
                                self.open_browser(job_id)
                            except RuntimeError:
                                pass
                        return
            except OSError:
                time.sleep(0.08)

        with self._lock:
            job = self._jobs[job_id]
            if job["status"] not in {"stopping", "stopped"}:
                job["status"] = "failed"
                job["phase_message"] = "Local puzzle server did not become ready"
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    def _read_browser_server(self, job_id: str) -> None:
        with self._lock:
            process: subprocess.Popen[str] = self._jobs[job_id]["process"]
        assert process.stdout is not None
        for raw in process.stdout:
            line = clean_log(raw)
            if line:
                with self._lock:
                    self._jobs[job_id]["logs"].append(line[-500:])
        returncode = process.wait()
        with self._lock:
            job = self._jobs[job_id]
            if job["status"] not in {"stopped", "failed", "stopping"}:
                job["status"] = "stopped" if returncode == 0 else "failed"
                job["phase_message"] = "Local puzzle stopped" if returncode == 0 else f"Local puzzle exited with code {returncode}"
                job["stopped_at"] = utc_now()
        self._remove_browser_state(job_id)

    def _read_worker(self, job_id: str) -> None:
        with self._lock:
            job = self._jobs[job_id]
            process: subprocess.Popen[str] = job["process"]
        assert process.stdout is not None
        for raw in process.stdout:
            if EVENT_PREFIX in raw:
                fragment = raw.split(EVENT_PREFIX, 1)[1].strip()
                try:
                    self._handle_event(job_id, json.loads(fragment))
                    continue
                except json.JSONDecodeError:
                    pass
            line = clean_log(raw)
            if line:
                with self._lock:
                    self._jobs[job_id]["logs"].append(line[-500:])
        returncode = process.wait()
        with self._lock:
            job = self._jobs[job_id]
            if job["status"] not in {"stopped", "failed"}:
                job["status"] = "stopped" if returncode == 0 or job["status"] == "stopping" else "failed"
                job["phase_message"] = "Environment stopped" if job["status"] == "stopped" else f"Worker exited with code {returncode}"
                job["stopped_at"] = utc_now()

    def _handle_event(self, job_id: str, event: dict[str, Any]) -> None:
        should_open = False
        with self._lock:
            job = self._jobs[job_id]
            event_name = event.get("event")
            if event_name == "phase":
                job["status"] = str(event.get("phase") or "booting")
                job["phase_message"] = str(event.get("message") or "Working")
            elif event_name == "ready":
                job["status"] = "running"
                job["phase_message"] = "VNC is ready"
                job["session"] = event.get("session") or {}
                job["ready_at"] = utc_now()
                should_open = bool(job["auto_open"])
            elif event_name == "error":
                job["status"] = "failed"
                job["phase_message"] = str(event.get("message") or "Environment failed")
                detail = clean_log(str(event.get("detail") or ""))
                if detail:
                    job["logs"].append(detail[-1200:])
            elif event_name == "log":
                job["logs"].append(str(event.get("message") or ""))
            elif event_name == "stopped":
                job["status"] = "stopped" if job["status"] != "failed" else "failed"
                job["phase_message"] = "Environment stopped"
                job["stopped_at"] = utc_now()
        if should_open:
            try:
                self.open_viewer(job_id)
            except RuntimeError:
                pass

    def open_viewer(self, job_id: str) -> dict[str, Any]:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job or job["status"] != "running" or not job.get("session"):
                raise RuntimeError("VNC is not ready yet")
            port = int(job["session"].get("vnc_port") or 0)
            password = str(job["session"].get("vnc_password") or "password")
            if not port:
                raise RuntimeError("runner did not expose a VNC port")
        opened, message = open_vnc_viewer(port, password)
        with self._lock:
            job = self._jobs[job_id]
            job["viewer_opened"] = opened
            job["logs"].append(message)
            return self._snapshot(job)

    def open_browser(self, job_id: str) -> dict[str, Any]:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job or job.get("kind") != "browser" or job["status"] != "running":
                raise RuntimeError("local browser puzzle is not ready yet")
            url = str((job.get("session") or {}).get("browser_url") or "")
            if not url:
                raise RuntimeError("local browser URL is unavailable")
        opened = bool(webbrowser.open(url))
        with self._lock:
            job = self._jobs[job_id]
            job["viewer_opened"] = opened
            job["logs"].append(f"Opened local browser at {url}" if opened else f"Open this local URL: {url}")
            return self._snapshot(job)

    def open(self, job_id: str) -> dict[str, Any]:
        with self._lock:
            job = self._jobs.get(job_id)
            kind = job.get("kind") if job else None
        if kind == "browser":
            return self.open_browser(job_id)
        return self.open_viewer(job_id)

    def stop(self, job_id: str) -> dict[str, Any]:
        remove_state = False
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                raise ValueError("unknown session")
            process: subprocess.Popen[str] | None = job.get("process")
            if not process or process.poll() is not None:
                job["status"] = "stopped"
                job["phase_message"] = "Environment stopped"
                job["stopped_at"] = utc_now()
                remove_state = job.get("kind") == "browser"
                result = self._snapshot(job)
            else:
                job["status"] = "stopping"
                job["phase_message"] = "Stopping environment"
                try:
                    os.killpg(process.pid, signal.SIGINT)
                except (ProcessLookupError, PermissionError):
                    process.send_signal(signal.SIGINT)
                threading.Thread(target=self._finish_stop, args=(job_id,), daemon=True).start()
                result = self._snapshot(job)
        if remove_state:
            self._remove_browser_state(job_id)
        return result

    def _finish_stop(self, job_id: str) -> None:
        with self._lock:
            process: subprocess.Popen[str] = self._jobs[job_id]["process"]
        try:
            process.wait(timeout=28)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        with self._lock:
            job = self._jobs[job_id]
            job["status"] = "stopped"
            job["phase_message"] = "Environment stopped"
            job["stopped_at"] = utc_now()
        self._remove_browser_state(job_id)

    def cleanup(self) -> None:
        with self._lock:
            active_jobs = [
                job_id
                for job_id, job in self._jobs.items()
                if job["status"] in {"queued", "booting", "running", "stopping"}
            ]
            active = []
            for job_id in active_jobs:
                process = self._jobs[job_id].get("process")
                self._jobs[job_id]["status"] = "stopping"
                self._jobs[job_id]["phase_message"] = "Dashboard shutdown: stopping environment"
                if process and process.poll() is None:
                    active.append((job_id, process))
        for _job_id, process in active:
            try:
                os.killpg(process.pid, signal.SIGINT)
            except (ProcessLookupError, PermissionError):
                try:
                    process.send_signal(signal.SIGINT)
                except ProcessLookupError:
                    pass
        deadline = time.monotonic() + 35
        for job_id, process in active:
            try:
                process.wait(timeout=max(0.1, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
            with self._lock:
                job = self._jobs[job_id]
                job["status"] = "stopped"
                job["phase_message"] = "Environment stopped"
                job["stopped_at"] = utc_now()
        with self._lock:
            for job_id in active_jobs:
                job = self._jobs[job_id]
                job["status"] = "stopped"
                job["phase_message"] = "Environment stopped"
                job["stopped_at"] = utc_now()
            browser_state_dirs = [
                Path(str(job["state_dir"]))
                for job in self._jobs.values()
                if job.get("kind") == "browser" and job.get("state_dir")
            ]
        for state_dir in browser_state_dirs:
            shutil.rmtree(state_dir, ignore_errors=True)

    def _remove_browser_state(self, job_id: str) -> None:
        with self._lock:
            job = self._jobs.get(job_id)
            state_dir = Path(str(job["state_dir"])) if job and job.get("kind") == "browser" and job.get("state_dir") else None
        if state_dir:
            shutil.rmtree(state_dir, ignore_errors=True)

    @staticmethod
    def _snapshot(job: dict[str, Any]) -> dict[str, Any]:
        output = {key: value for key, value in job.items() if key not in {"process", "command", "created_ts"}}
        output["logs"] = list(job.get("logs") or [])
        output["uptime_seconds"] = max(0, int(time.time() - job["created_ts"])) if job["status"] in {"booting", "running", "stopping"} else None
        return output

class EvaluationManager:
    def __init__(self, runner: str) -> None:
        self.runner = runner
        self._jobs: dict[str, dict[str, Any]] = {}
        self._lock = threading.RLock()

    def list(self) -> list[dict[str, Any]]:
        with self._lock:
            return [self._snapshot(job) for job in sorted(self._jobs.values(), key=lambda item: item["created_ts"], reverse=True)]

    def build_command(self, payload: dict[str, Any]) -> tuple[list[str], dict[str, Any]]:
        catalog = environment_index()
        environment_id = str(payload.get("environment_id") or "")
        environment = catalog.get(environment_id)
        if environment is None:
            raise ValueError("unknown environment")
        task_id = str(payload.get("task_id") or (environment["tasks"][0]["id"] if environment["tasks"] else ""))
        if task_id not in {task["id"] for task in environment["tasks"]}:
            raise ValueError("unknown task")
        agent = str(payload.get("agent") or "Qwen3VLAgent")
        model = str(payload.get("model") or "qwen3-vl")
        if not SAFE_AGENT.fullmatch(agent):
            raise ValueError("invalid agent name")
        if not SAFE_MODEL.fullmatch(model):
            raise ValueError("invalid model identifier")
        seed = max(0, min(int(payload.get("seed", 42)), 2_147_483_647))
        steps = max(1, min(int(payload.get("steps", 50)), 1000))
        experiment = str(payload.get("experiment") or f"captcha-hub-{datetime.now().strftime('%Y%m%d-%H%M%S')}")
        if not SAFE_EXPERIMENT.fullmatch(experiment):
            raise ValueError("invalid experiment name")
        command = [
            sys.executable,
            "-m",
            "gym_anything.cli",
            "benchmark",
            str(REPO_ROOT / environment["environment_path"]),
            "--benchmark",
            "weird_captcha_gym",
            "--task",
            task_id,
            "--agent",
            agent,
            "--model",
            model,
            "--steps",
            str(steps),
            "--seed",
            str(seed),
            "--exp-name",
            experiment,
        ]
        if bool(payload.get("fast_io")):
            command.append("--fast-io")
        details = {
            "environment_id": environment_id,
            "title": environment["title"],
            "task_id": task_id,
            "agent": agent,
            "model": model,
            "seed": seed,
            "steps": steps,
            "experiment": experiment,
        }
        return command, details

    def start(self, payload: dict[str, Any]) -> dict[str, Any]:
        command, details = self.build_command(payload)
        preview_only = bool(payload.get("preview_only", True))
        job_id = uuid.uuid4().hex[:10]
        job: dict[str, Any] = {
            "id": job_id,
            "kind": "evaluation",
            **details,
            "status": "preview" if preview_only else "queued",
            "created_at": utc_now(),
            "created_ts": time.time(),
            "completed_at": None,
            "returncode": None,
            "logs": deque(maxlen=240),
            "command": command,
            "process": None,
        }
        job["logs"].append(" ".join(command))
        with self._lock:
            self._jobs[job_id] = job
        if preview_only:
            return self._snapshot(job)
        process = subprocess.Popen(
            command,
            cwd=REPO_ROOT,
            env=process_env(self.runner),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            start_new_session=True,
        )
        with self._lock:
            job["process"] = process
            job["status"] = "running"
        threading.Thread(target=self._read_process, args=(job_id,), daemon=True).start()
        return self._snapshot(job)

    def _read_process(self, job_id: str) -> None:
        with self._lock:
            process: subprocess.Popen[str] = self._jobs[job_id]["process"]
        assert process.stdout is not None
        for raw in process.stdout:
            line = clean_log(raw)
            if line:
                with self._lock:
                    self._jobs[job_id]["logs"].append(line[-700:])
        returncode = process.wait()
        with self._lock:
            job = self._jobs[job_id]
            job["returncode"] = returncode
            job["status"] = "completed" if returncode == 0 else ("canceled" if job["status"] == "canceling" else "failed")
            job["completed_at"] = utc_now()

    def stop(self, job_id: str) -> dict[str, Any]:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                raise ValueError("unknown evaluation")
            process: subprocess.Popen[str] | None = job.get("process")
            if not process or process.poll() is not None:
                return self._snapshot(job)
            job["status"] = "canceling"
            try:
                os.killpg(process.pid, signal.SIGINT)
            except (ProcessLookupError, PermissionError):
                process.send_signal(signal.SIGINT)
            return self._snapshot(job)

    def cleanup(self) -> None:
        with self._lock:
            running = [job for job in self._jobs.values() if job.get("process") and job["process"].poll() is None]
            for job in running:
                job["status"] = "canceling"
        for job in running:
            try:
                os.killpg(job["process"].pid, signal.SIGINT)
            except (ProcessLookupError, PermissionError):
                try:
                    job["process"].send_signal(signal.SIGINT)
                except ProcessLookupError:
                    pass
        deadline = time.monotonic() + 35
        for job in running:
            process: subprocess.Popen[str] = job["process"]
            try:
                process.wait(timeout=max(0.1, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass

    @staticmethod
    def _snapshot(job: dict[str, Any]) -> dict[str, Any]:
        output = {key: value for key, value in job.items() if key not in {"process", "created_ts"}}
        output["logs"] = list(job.get("logs") or [])
        output["command"] = " ".join(job.get("command") or [])
        return output


class DashboardServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        runner: str,
        *,
        review_path: Path | None = None,
        companion_token: str | None = None,
        allowed_origins: set[str] | None = None,
    ) -> None:
        super().__init__(address, DashboardHandler)
        self.sessions = SessionManager(runner)
        self.evaluations = EvaluationManager(runner)
        self.reviews = EnvironmentReviewStore(review_path)
        self.runner = runner
        self.companion_token = companion_token
        self.allowed_origins = frozenset(origin.rstrip("/") for origin in (allowed_origins or set()) if origin)

    def cleanup(self) -> None:
        self.sessions.cleanup()
        self.evaluations.cleanup()


class DashboardHandler(BaseHTTPRequestHandler):
    server: DashboardServer

    def do_OPTIONS(self) -> None:
        if not self._origin_is_allowed():
            self._send_json({"error": "origin is not allowed by the local companion"}, status=HTTPStatus.FORBIDDEN)
            return
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Allow", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Captcha-Bench-Token")
        self.send_header("Access-Control-Max-Age", "600")
        if self.headers.get("Access-Control-Request-Private-Network", "").lower() == "true":
            self.send_header("Access-Control-Allow-Private-Network", "true")
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/api/health":
            if not self._origin_is_allowed():
                self._send_json({"error": "origin is not allowed by the local companion"}, status=HTTPStatus.FORBIDDEN)
                return
            self._send_json({
                "ok": True,
                "runner": self.server.runner,
                "time": utc_now(),
                "mode": "companion" if self.server.companion_token else "local",
                "auth_required": bool(self.server.companion_token),
            })
            return
        if path.startswith("/api/") and not self._authorize_api_request():
            return
        if path == "/api/catalog":
            self._send_json(build_catalog())
        elif path == "/api/reviews":
            self._send_json(self.server.reviews.snapshot())
        elif path == "/api/system":
            self._send_json({
                "runner": self.server.runner,
                "agents": available_agents(),
                "platform": sys.platform,
                "repo_root": str(REPO_ROOT),
                "review_path": str(self.server.reviews.path),
                "companion": bool(self.server.companion_token),
            })
        elif path == "/api/sessions":
            self._send_json({"sessions": self.server.sessions.list()})
        elif path == "/api/evaluations":
            self._send_json({"evaluations": self.server.evaluations.list()})
        elif path.startswith("/media/"):
            self._serve_under(BENCHMARK_ROOT, unquote(path.removeprefix("/media/")), cache=True)
        elif path.startswith("/static/"):
            self._serve_under(STATIC_ROOT, unquote(path.removeprefix("/static/")), cache=False)
        elif path in {"/", "/index.html"}:
            self._serve_file(STATIC_ROOT / "index.html", cache=False)
        elif path.startswith("/api/"):
            self._send_json({"error": "not found"}, status=HTTPStatus.NOT_FOUND)
        else:
            self._serve_file(STATIC_ROOT / "index.html", cache=False)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        if not self._authorize_api_request():
            return
        try:
            payload = self._read_json()
            if path == "/api/sessions":
                environment_id = str(payload.get("environment_id") or "")
                catalog = environment_index()
                environment = catalog.get(environment_id)
                if not environment:
                    raise ValueError("unknown environment")
                task_id = str(payload.get("task_id") or (environment["tasks"][0]["id"] if environment["tasks"] else ""))
                mode = str(payload.get("mode") or "vnc")
                if mode not in {"browser", "vnc"}:
                    raise ValueError("session mode must be browser or vnc")
                starter = self.server.sessions.start_browser if mode == "browser" else self.server.sessions.start
                result = starter(
                    environment_id,
                    task_id,
                    seed=max(0, min(int(payload.get("seed", 42)), 2_147_483_647)),
                    auto_open=bool(payload.get("auto_open", True)),
                )
                self._send_json(result, status=HTTPStatus.ACCEPTED)
                return
            if path == "/api/evaluations":
                result = self.server.evaluations.start(payload)
                self._send_json(result, status=HTTPStatus.ACCEPTED)
                return
            match = re.fullmatch(r"/api/reviews/([^/]+)", path)
            if match:
                environment_id = unquote(match.group(1))
                review = self.server.reviews.update(environment_id, payload)
                self._send_json({"id": environment_id, "review": review, "stats": self.server.reviews.snapshot()["stats"]})
                return
            match = re.fullmatch(r"/api/sessions/([a-f0-9]+)/open", path)
            if match:
                self._send_json(self.server.sessions.open(match.group(1)))
                return
            match = re.fullmatch(r"/api/sessions/([a-f0-9]+)/stop", path)
            if match:
                self._send_json(self.server.sessions.stop(match.group(1)))
                return
            match = re.fullmatch(r"/api/evaluations/([a-f0-9]+)/stop", path)
            if match:
                self._send_json(self.server.evaluations.stop(match.group(1)))
                return
            self._send_json({"error": "not found"}, status=HTTPStatus.NOT_FOUND)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
        except RuntimeError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.CONFLICT)
        except Exception as exc:
            self._send_json({"error": f"dashboard request failed: {exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)

    def do_DELETE(self) -> None:
        parsed = urlparse(self.path)
        if not self._authorize_api_request():
            return
        session_match = re.fullmatch(r"/api/sessions/([a-f0-9]+)", parsed.path)
        eval_match = re.fullmatch(r"/api/evaluations/([a-f0-9]+)", parsed.path)
        try:
            if session_match:
                self._send_json(self.server.sessions.stop(session_match.group(1)))
            elif eval_match:
                self._send_json(self.server.evaluations.stop(eval_match.group(1)))
            else:
                self._send_json({"error": "not found"}, status=HTTPStatus.NOT_FOUND)
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.NOT_FOUND)

    def _origin_is_allowed(self) -> bool:
        origin = str(self.headers.get("Origin") or "").rstrip("/")
        if not origin:
            return True
        host = str(self.headers.get("Host") or "")
        same_origin = origin in {f"http://{host}", f"https://{host}"}
        return same_origin or origin in self.server.allowed_origins

    def _send_cors_headers(self) -> None:
        origin = str(self.headers.get("Origin") or "").rstrip("/")
        if origin and self._origin_is_allowed():
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")

    def _authorize_api_request(self) -> bool:
        if not self._origin_is_allowed():
            self._send_json({"error": "origin is not allowed by the local companion"}, status=HTTPStatus.FORBIDDEN)
            return False
        expected = self.server.companion_token
        supplied = str(self.headers.get("X-Captcha-Bench-Token") or "")
        if expected and not hmac.compare_digest(expected, supplied):
            self._send_json({"error": "pairing key is missing or invalid"}, status=HTTPStatus.UNAUTHORIZED)
            return False
        return True

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("content-length", "0") or 0)
        if length > 1_000_000:
            raise ValueError("request body is too large")
        if length == 0:
            return {}
        try:
            value = json.loads(self.rfile.read(length))
        except json.JSONDecodeError as exc:
            raise ValueError("invalid JSON body") from exc
        if not isinstance(value, dict):
            raise ValueError("JSON body must be an object")
        return value

    def _send_json(self, payload: object, *, status: HTTPStatus = HTTPStatus.OK) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(data)

    def _serve_under(self, root: Path, relative: str, *, cache: bool) -> None:
        candidate = (root / relative).resolve()
        try:
            candidate.relative_to(root.resolve())
        except ValueError:
            self.send_error(HTTPStatus.FORBIDDEN)
            return
        self._serve_file(candidate, cache=cache)

    def _serve_file(self, path: Path, *, cache: bool, content_type: str | None = None, disposition: str | None = None) -> None:
        if not path.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        size = path.stat().st_size
        content_type = content_type or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(size))
        self.send_header("Cache-Control", "public, max-age=3600" if cache else "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        if disposition:
            safe_name = re.sub(r"[^\x20-\x7E]", "_", path.name).replace('"', "")
            encoded_name = quote(path.name, safe="")
            self.send_header("Content-Disposition", f"{disposition}; filename=\"{safe_name}\"; filename*=UTF-8''{encoded_name}")
        self.end_headers()
        try:
            with path.open("rb") as handle:
                while chunk := handle.read(128 * 1024):
                    self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, _format: str, *_args: object) -> None:
        return


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Serve the CAPTCHA Bench visual environment dashboard.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8767)
    parser.add_argument("--runner", choices=sorted(RUNNERS), default=os.environ.get("GYM_ANYTHING_RUNNER", "avf"))
    parser.add_argument("--review-path", type=Path, help="Override the persistent environment review ledger path")
    parser.add_argument("--companion", action="store_true", help="Run as the authenticated localhost companion for a shared static dashboard")
    parser.add_argument("--allow-origin", action="append", default=[], help="Exact shared-dashboard origin allowed to call the companion (repeatable)")
    parser.add_argument("--token-path", type=Path, default=DEFAULT_TOKEN_PATH, help="Persistent pairing-key file used in companion mode")
    parser.add_argument("--dashboard-url", help="Shared dashboard URL to open when --open is used in companion mode")
    parser.add_argument("--open", action="store_true", help="Open the dashboard in the default browser")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.companion and not is_loopback_host(args.host):
        raise SystemExit("companion mode must bind to localhost/loopback; refusing a network-visible address")
    token = load_or_create_companion_token(args.token_path) if args.companion else None
    server = DashboardServer(
        (args.host, args.port),
        args.runner,
        review_path=args.review_path,
        companion_token=token,
        allowed_origins=set(args.allow_origin),
    )
    atexit.register(server.cleanup)
    url = f"http://{args.host}:{args.port}"
    print(f"CAPTCHA Bench {'local companion' if args.companion else 'dashboard'}: {url}")
    print(f"Runner: {args.runner} · Ctrl+C to stop")
    if args.companion:
        print(f"Pairing key: {token}")
        print(f"Allowed dashboard origins: {', '.join(sorted(server.allowed_origins)) or 'none (same-origin requests only)'}")
    if args.open:
        destination = args.dashboard_url if args.companion and args.dashboard_url else url
        threading.Timer(0.35, lambda: webbrowser.open(destination)).start()

    def request_shutdown(_signum: int, _frame: object) -> None:
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, request_shutdown)
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, request_shutdown)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.cleanup()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
