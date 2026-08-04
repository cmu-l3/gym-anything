"""The stranger test, remote leg: by-name create through a real worker.

The stranger benchmark is installed as a package only this process knows;
the client creates the environment by (benchmark, env_name, task_id) with a
content digest, the worker resolves against its own installation, and a
full episode runs over HTTP. Also pins the two remote laws directly: busy
environments are never reaped (L3), and digest mismatches are refused
rather than silently running the wrong task (L3).
"""

from __future__ import annotations

import importlib
import json
import sys
import threading
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import requests

from tests.test_stranger_party import build_stranger_benchmark


def _start_worker():
    from werkzeug.serving import make_server

    from gym_anything.remote import worker as worker_mod

    server = make_server("127.0.0.1", 0, worker_mod.app)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return worker_mod, server, thread


class StrangerRemoteTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = TemporaryDirectory()
        tmp = Path(cls._tmp.name)
        cls.episodes = tmp / "episodes"
        cls.episodes.mkdir()
        pkg = tmp / "pkgs" / "stranger_remote_world"
        pkg.mkdir(parents=True)
        (pkg / "__init__.py").write_text("")
        build_stranger_benchmark(pkg, cls.episodes)
        sys.path.insert(0, str(tmp / "pkgs"))
        importlib.invalidate_caches()

        cls.worker_mod, cls.server, cls.thread = _start_worker()
        cls.url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.thread.join(timeout=5)
        sys.path.remove(str(Path(cls._tmp.name) / "pkgs"))
        sys.modules.pop("stranger_remote_world", None)
        cls._tmp.cleanup()

    def test_full_episode_by_name_over_http(self):
        from gym_anything.remote import RemoteGymEnv

        env = RemoteGymEnv.from_benchmark(
            remote_url=self.url,
            benchmark="stranger_remote_world",
            env_name="stranger_env",
            task_id="deliver_t1",
            timeout=60,
            worker_reset_policy=None,
        )
        try:
            obs = env.reset(seed=3)
            self.assertIn("telemetry", obs)
            obs, _, done, _ = env.step([{"action": "wait", "time": 5}])
            self.assertFalse(done)
            obs, _, done, _ = env.step([{"action": "deliver", "target": "parcel"}])
            self.assertEqual(obs["telemetry"]["ticks"], 6)
            obs, reward, done, info = env.step([], mark_done=True)
            self.assertTrue(done)
            verifier = info.get("verifier") or {}
            self.assertTrue(verifier.get("passed"), msg=f"verifier said: {verifier}")
        finally:
            env.close()

    def test_digest_mismatch_is_refused(self):
        response = requests.post(f"{self.url}/envs/create", json={
            "benchmark": "stranger_remote_world",
            "env_name": "stranger_env",
            "task_id": "deliver_t1",
            "task_digest": "sha256:" + "0" * 64,
        }, timeout=30)
        self.assertEqual(response.status_code, 409)
        body = response.json()
        self.assertIn("task content mismatch", body["error"])
        self.assertIn("worker_digest", body)

    def test_busy_environments_are_never_reaped(self):
        response = requests.post(f"{self.url}/envs/create", json={
            "benchmark": "stranger_remote_world",
            "env_name": "stranger_env",
            "task_id": "deliver_t1",
        }, timeout=60)
        self.assertEqual(response.status_code, 201)
        env_id = response.json()["env_id"]
        worker = self.worker_mod
        try:
            old_timeout = worker.env_manager.timeout_seconds
            worker.env_manager.timeout_seconds = 0
            try:
                worker._mark_env_busy(env_id)
                worker.env_manager._cleanup_idle_environments()
                self.assertIn(env_id, worker.env_registry, "busy env was reaped")
                worker._mark_env_free(env_id)
                worker.env_manager._cleanup_idle_environments()
                self.assertNotIn(env_id, worker.env_registry, "idle env survived")
            finally:
                worker.env_manager.timeout_seconds = old_timeout
        finally:
            requests.post(f"{self.url}/envs/{env_id}/close", timeout=30)


if __name__ == "__main__":
    unittest.main()
