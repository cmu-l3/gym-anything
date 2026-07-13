#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import atexit
import json
import mimetypes
import os
import re
import signal
import subprocess
import sys
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
from urllib.parse import parse_qs, quote, unquote, urlparse


DASHBOARD_ROOT = Path(__file__).resolve().parent
STATIC_ROOT = DASHBOARD_ROOT / "static"
sys.path.insert(0, str(DASHBOARD_ROOT))

try:  # Package import in tests; local import when executed as a script.
    from .catalog import BENCHMARK_ROOT, REPO_ROOT, build_catalog, environment_index
    from .reviews import EnvironmentReviewStore
    from .atlas import (
        AtlasCurationStore, SOURCES_ROOT, artifact_page, build_atlas, instance_detail, instance_page,
        source_detail, specimen_detail,
    )
except ImportError:  # pragma: no cover - exercised by the script entrypoint.
    from catalog import BENCHMARK_ROOT, REPO_ROOT, build_catalog, environment_index  # type: ignore[no-redef]
    from reviews import EnvironmentReviewStore  # type: ignore[no-redef]
    from atlas import (  # type: ignore[no-redef]
        AtlasCurationStore, SOURCES_ROOT, artifact_page, build_atlas, instance_detail, instance_page,
        source_detail, specimen_detail,
    )


EVENT_PREFIX = "__CAPTCHA_HUB_EVENT__"
ANSI_ESCAPE = re.compile(r"(?:\x1B[@-_][0-?]*[ -/]*[@-~])|(?:\x1B\][^\x07]*(?:\x07|\x1B\\))")
SAFE_AGENT = re.compile(r"^[A-Za-z][A-Za-z0-9_]{1,80}$")
SAFE_MODEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_./:+-]{0,180}$")
SAFE_EXPERIMENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,100}$")
RUNNERS = {"avf", "qemu", "qemu_native", "docker", "local"}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def clean_log(line: str) -> str:
    return ANSI_ESCAPE.sub("", line).replace("\r", "").strip()


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

    def stop(self, job_id: str) -> dict[str, Any]:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                raise ValueError("unknown session")
            process: subprocess.Popen[str] | None = job.get("process")
            if not process or process.poll() is not None:
                job["status"] = "stopped"
                return self._snapshot(job)
            job["status"] = "stopping"
            job["phase_message"] = "Stopping environment"
            try:
                os.killpg(process.pid, signal.SIGINT)
            except (ProcessLookupError, PermissionError):
                process.send_signal(signal.SIGINT)
            threading.Thread(target=self._finish_stop, args=(job_id,), daemon=True).start()
            return self._snapshot(job)

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

    def cleanup(self) -> None:
        with self._lock:
            active = [
                (job_id, job.get("process"))
                for job_id, job in self._jobs.items()
                if job["status"] in {"queued", "booting", "running", "stopping"}
                and job.get("process")
                and job["process"].poll() is None
            ]
            for job_id, _process in active:
                self._jobs[job_id]["status"] = "stopping"
                self._jobs[job_id]["phase_message"] = "Dashboard shutdown: stopping environment"
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
        curation_path: Path | None = None,
        review_path: Path | None = None,
    ) -> None:
        super().__init__(address, DashboardHandler)
        self.sessions = SessionManager(runner)
        self.evaluations = EvaluationManager(runner)
        self.atlas = AtlasCurationStore(curation_path)
        self.reviews = EnvironmentReviewStore(review_path)
        self.runner = runner

    def cleanup(self) -> None:
        self.sessions.cleanup()
        self.evaluations.cleanup()


class DashboardHandler(BaseHTTPRequestHandler):
    server: DashboardServer

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Allow", "GET, POST, DELETE, OPTIONS")
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/api/health":
            self._send_json({"ok": True, "runner": self.server.runner, "time": utc_now()})
        elif path == "/api/catalog":
            self._send_json(build_catalog())
        elif path == "/api/reviews":
            self._send_json(self.server.reviews.snapshot())
        elif path == "/api/atlas":
            self._send_json(build_atlas(self.server.atlas))
        elif path == "/api/atlas/instances":
            query = parse_qs(parsed.query)
            try:
                self._send_json(instance_page(
                    query=str(query.get("query", [""])[0]),
                    source=str(query.get("source", ["all"])[0]),
                    family=str(query.get("family", ["all"])[0]),
                    record_type=str(query.get("record_type", ["all"])[0]),
                    decision=str(query.get("decision", ["all"])[0]),
                    offset=int(query.get("offset", [0])[0]),
                    limit=int(query.get("limit", [36])[0]),
                    store=self.server.atlas,
                ))
            except (TypeError, ValueError) as exc:
                self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
        elif match := re.fullmatch(r"/api/atlas/instances/(.+)", path):
            try:
                self._send_json(instance_detail(unquote(match.group(1)), self.server.atlas))
            except ValueError as exc:
                self._send_json({"error": str(exc)}, status=HTTPStatus.NOT_FOUND)
        elif match := re.fullmatch(r"/api/atlas/items/(.+)", path):
            try:
                self._send_json(specimen_detail(unquote(match.group(1)), self.server.atlas))
            except ValueError as exc:
                self._send_json({"error": str(exc)}, status=HTTPStatus.NOT_FOUND)
        elif match := re.fullmatch(r"/api/atlas/specimens/(.+)", path):
            try:
                self._send_json(specimen_detail(unquote(match.group(1)), self.server.atlas))
            except ValueError as exc:
                self._send_json({"error": str(exc)}, status=HTTPStatus.NOT_FOUND)
        elif match := re.fullmatch(r"/api/atlas/sources/([^/]+)/artifacts", path):
            query = parse_qs(parsed.query)
            try:
                self._send_json(artifact_page(
                    unquote(match.group(1)),
                    kind=str(query.get("kind", ["all"])[0]),
                    offset=int(query.get("offset", [0])[0]),
                    limit=int(query.get("limit", [48])[0]),
                ))
            except (TypeError, ValueError) as exc:
                self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
        elif match := re.fullmatch(r"/api/atlas/sources/([^/]+)", path):
            try:
                self._send_json(source_detail(unquote(match.group(1)), self.server.atlas))
            except ValueError as exc:
                self._send_json({"error": str(exc)}, status=HTTPStatus.NOT_FOUND)
        elif path == "/api/system":
            self._send_json({"runner": self.server.runner, "agents": available_agents(), "platform": sys.platform, "repo_root": str(REPO_ROOT), "review_path": str(self.server.reviews.path)})
        elif path == "/api/sessions":
            self._send_json({"sessions": self.server.sessions.list()})
        elif path == "/api/evaluations":
            self._send_json({"evaluations": self.server.evaluations.list()})
        elif path.startswith("/media/"):
            self._serve_under(BENCHMARK_ROOT, unquote(path.removeprefix("/media/")), cache=True)
        elif path.startswith("/atlas-media/"):
            self._serve_atlas_artifact(unquote(path.removeprefix("/atlas-media/")))
        elif path.startswith("/static/"):
            self._serve_under(STATIC_ROOT, unquote(path.removeprefix("/static/")), cache=False)
        elif path in {"/", "/index.html"}:
            self._serve_file(STATIC_ROOT / "index.html", cache=False)
        else:
            self._serve_file(STATIC_ROOT / "index.html", cache=False)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        try:
            payload = self._read_json()
            if path == "/api/sessions":
                environment_id = str(payload.get("environment_id") or "")
                catalog = environment_index()
                environment = catalog.get(environment_id)
                if not environment:
                    raise ValueError("unknown environment")
                task_id = str(payload.get("task_id") or (environment["tasks"][0]["id"] if environment["tasks"] else ""))
                result = self.server.sessions.start(
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
            match = re.fullmatch(r"/api/atlas/(?:items|instances|specimens)/(.+)/curation", path)
            if match:
                item_id = unquote(match.group(1))
                curation = self.server.atlas.update(item_id, payload)
                atlas = build_atlas(self.server.atlas)
                self._send_json({"id": item_id, "curation": curation, "stats": atlas["stats"], "layer_curation": atlas["layer_curation"]})
                return
            match = re.fullmatch(r"/api/sessions/([a-f0-9]+)/open", path)
            if match:
                self._send_json(self.server.sessions.open_viewer(match.group(1)))
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

    def _serve_atlas_artifact(self, relative: str) -> None:
        candidate = (SOURCES_ROOT / relative).resolve()
        try:
            candidate.relative_to(SOURCES_ROOT.resolve())
        except ValueError:
            self.send_error(HTTPStatus.FORBIDDEN)
            return
        suffix = candidate.suffix.lower()
        browser_safe = suffix in {
            ".avif", ".gif", ".jpeg", ".jpg", ".m4a", ".m4v", ".mov", ".mp3", ".mp4", ".oga", ".ogg",
            ".pdf", ".png", ".wav", ".webm", ".webp",
        }
        text_like = suffix in {
            ".c", ".cc", ".cpp", ".css", ".csv", ".gd", ".go", ".h", ".html", ".java", ".js", ".json",
            ".jsonl", ".jsx", ".kt", ".md", ".php", ".py", ".rb", ".rs", ".rst", ".sh", ".sql", ".svelte",
            ".swift", ".toml", ".ts", ".tsv", ".tsx", ".txt", ".vtt", ".vue", ".xml", ".yaml", ".yml",
        }
        content_type = None if browser_safe else ("text/plain; charset=utf-8" if text_like else "application/octet-stream")
        disposition = "inline" if browser_safe else "attachment"
        self._serve_file(candidate, cache=True, content_type=content_type, disposition=disposition)

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
    parser.add_argument("--open", action="store_true", help="Open the dashboard in the default browser")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    server = DashboardServer((args.host, args.port), args.runner, review_path=args.review_path)
    atexit.register(server.cleanup)
    url = f"http://{args.host}:{args.port}"
    print(f"CAPTCHA Bench dashboard: {url}")
    print(f"Runner: {args.runner} · Ctrl+C to stop")
    if args.open:
        threading.Timer(0.35, lambda: webbrowser.open(url)).start()

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
