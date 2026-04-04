from __future__ import annotations

import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import closing
from pathlib import Path
from typing import Callable

import requests

from gym_anything.remote import RemoteGymEnv


def _pick_free_port() -> int:
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def _eventually(
    check: Callable[[], bool],
    *,
    timeout: float = 20.0,
    interval: float = 0.1,
    description: str,
) -> None:
    deadline = time.time() + timeout
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            if check():
                return
        except Exception as exc:  # pragma: no cover - surfaced in timeout message
            last_error = exc
        time.sleep(interval)
    if last_error is not None:
        raise AssertionError(f"Timed out waiting for {description}: {last_error}") from last_error
    raise AssertionError(f"Timed out waiting for {description}")


class _ManagedProcess:
    def __init__(self, args: list[str], *, cwd: Path, log_path: Path, env: dict[str, str]) -> None:
        self._args = args
        self._cwd = cwd
        self._log_path = log_path
        self._env = env
        self._proc: subprocess.Popen[bytes] | None = None
        self._log_handle = None

    @property
    def returncode(self) -> int | None:
        return None if self._proc is None else self._proc.poll()

    def start(self) -> None:
        self._log_handle = self._log_path.open("wb")
        self._proc = subprocess.Popen(
            self._args,
            cwd=self._cwd,
            env=self._env,
            stdout=self._log_handle,
            stderr=subprocess.STDOUT,
        )

    def stop(self) -> None:
        if self._proc is None:
            return
        if self._proc.poll() is None:
            self._proc.send_signal(signal.SIGTERM)
            try:
                self._proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self._proc.kill()
                self._proc.wait(timeout=10)
        if self._log_handle is not None:
            self._log_handle.close()

    def assert_running(self) -> None:
        if self.returncode is not None:
            raise AssertionError(
                f"Process exited early with code {self.returncode}: {self._log_path.read_text(encoding='utf-8', errors='replace')}"
            )


class RemoteClusterIntegrationTests(unittest.TestCase):
    def test_master_and_workers_route_real_remote_envs_end_to_end(self) -> None:
        repo_root = Path(__file__).resolve().parents[1]
        py_path_parts = [str(repo_root / "src"), str(repo_root)]
        existing_py_path = os.environ.get("PYTHONPATH")
        if existing_py_path:
            py_path_parts.append(existing_py_path)
        proc_env = os.environ.copy()
        proc_env["PYTHONPATH"] = os.pathsep.join(py_path_parts)
        proc_env["PYTHONUNBUFFERED"] = "1"

        master_port = _pick_free_port()
        worker_ports = [_pick_free_port(), _pick_free_port()]
        master_url = f"http://127.0.0.1:{master_port}"

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            master = _ManagedProcess(
                [
                    sys.executable,
                    "-m",
                    "gym_anything.remote.master",
                    "--host",
                    "127.0.0.1",
                    "--port",
                    str(master_port),
                    "--dev",
                ],
                cwd=repo_root,
                log_path=tmp_path / "master.log",
                env=proc_env,
            )
            workers = [
                _ManagedProcess(
                    [
                        sys.executable,
                        "-m",
                        "gym_anything.remote.worker",
                        "--host",
                        "127.0.0.1",
                        "--port",
                        str(port),
                        "--master-url",
                        master_url,
                        "--max-envs",
                        "2",
                        "--heartbeat-interval",
                        "1",
                        "--advertise-host",
                        "127.0.0.1",
                    ],
                    cwd=repo_root,
                    log_path=tmp_path / f"worker-{port}.log",
                    env=proc_env,
                )
                for port in worker_ports
            ]
            envs: list[RemoteGymEnv] = []
            try:
                master.start()
                _eventually(
                    lambda: requests.get(f"{master_url}/health", timeout=1).status_code == 200,
                    description="master health endpoint",
                )
                for worker in workers:
                    worker.start()

                def _cluster_ready() -> bool:
                    response = requests.get(f"{master_url}/health", timeout=1)
                    payload = response.json()
                    return response.status_code == 200 and payload.get("healthy_workers") == 2

                _eventually(_cluster_ready, description="two healthy workers")

                workers_payload = requests.get(f"{master_url}/workers/list", timeout=2).json()
                self.assertEqual(workers_payload["total_workers"], 2)
                for worker in workers_payload["workers"]:
                    self.assertTrue(worker["url"].startswith("http://127.0.0.1:"))

                spec = {
                    "id": "remote-cluster-local",
                    "runner": "local",
                    "observation": [{"type": "rgb_screen", "fps": 1, "resolution": [64, 64]}],
                    "action": [{"type": "mouse"}],
                    "recording": {"enable": False, "output_dir": str(tmp_path / "artifacts")},
                }

                for seed in (1, 2):
                    env = RemoteGymEnv.make(remote_url=master_url, env=spec, timeout=10)
                    envs.append(env)
                    obs = env.reset(seed=seed)
                    self.assertIn("screen", obs)
                    session = env.get_session_info()
                    self.assertIsNotNone(session)
                    self.assertEqual(session.runner_name, "LocalRunner")

                envs_payload = requests.get(f"{master_url}/envs/list", timeout=2).json()
                self.assertEqual(envs_payload["total"], 2)
                self.assertEqual(
                    len({entry["worker_id"] for entry in envs_payload["environments"].values()}),
                    2,
                )

                obs = envs[0].capture_observation()
                self.assertIn("screen", obs)
                step_obs, reward, done, info = envs[0].step([], wait_between_actions=0.0, mark_done=False)
                self.assertIn("screen", step_obs)
                self.assertEqual(reward, 0.0)
                self.assertFalse(done)
                self.assertEqual(info["step"], 0)

                def _metrics_ready() -> bool:
                    payload = requests.get(f"{master_url}/api/metrics", timeout=2).json()["cluster"]
                    return (
                        payload["total_envs"] == 2
                        and len(payload["aggregated"]["active_envs"]) == 2
                        and payload["aggregated"]["total_requests"] >= 6
                    )

                _eventually(_metrics_ready, timeout=10, description="aggregated worker metrics")

                dashboard = requests.get(f"{master_url}/dashboard", timeout=2)
                self.assertEqual(dashboard.status_code, 200)
                self.assertIn("Gym-Anything Master Dashboard", dashboard.text)

                for env in envs:
                    env.close()

                def _all_envs_closed() -> bool:
                    payload = requests.get(f"{master_url}/envs/list", timeout=2).json()
                    return payload["total"] == 0

                _eventually(_all_envs_closed, timeout=10, description="environment cleanup")
            finally:
                for env in envs:
                    try:
                        env.close()
                    except Exception:
                        pass
                for worker in workers:
                    worker.stop()
                master.stop()
