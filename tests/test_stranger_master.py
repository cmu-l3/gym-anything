"""The stranger test, master leg: routed create through the full stack.

A real master and a real worker subprocess; the worker is started with
``--must-support-runner <locator>`` for a runner class core has never met,
probes it via the class's own doctor_status, and advertises the exact
string the client's spec carries. The client creates by benchmark name;
the master routes on the advertised locator; the worker resolves the
benchmark against its own PYTHONPATH. A full episode runs end to end.
"""

from __future__ import annotations

import importlib
import os
import sys
import tempfile
import unittest
from pathlib import Path

import requests

from gym_anything.remote import RemoteGymEnv
from tests.test_remote_cluster_integration import (
    _eventually,
    _ManagedProcess,
    _pick_free_port,
)
from tests.test_stranger_party import STRANGER_LOCATOR, build_stranger_benchmark


class StrangerThroughMasterTest(unittest.TestCase):
    def test_full_episode_routed_by_master(self) -> None:
        repo_root = Path(__file__).resolve().parents[1]

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            episodes = tmp_path / "episodes"
            episodes.mkdir()
            pkg = tmp_path / "pkgs" / "stranger_master_world"
            pkg.mkdir(parents=True)
            (pkg / "__init__.py").write_text("")
            build_stranger_benchmark(pkg, episodes)

            # Client side resolves the benchmark from this process's path;
            # the worker subprocess resolves it from PYTHONPATH — two
            # installations agreeing only through the by-name protocol.
            sys.path.insert(0, str(tmp_path / "pkgs"))
            importlib.invalidate_caches()

            py_path_parts = [str(repo_root / "src"), str(repo_root), str(tmp_path / "pkgs")]
            if os.environ.get("PYTHONPATH"):
                py_path_parts.append(os.environ["PYTHONPATH"])
            proc_env = os.environ.copy()
            proc_env["PYTHONPATH"] = os.pathsep.join(py_path_parts)
            proc_env["PYTHONUNBUFFERED"] = "1"

            master_port = _pick_free_port()
            worker_port = _pick_free_port()
            master_url = f"http://127.0.0.1:{master_port}"

            master = _ManagedProcess(
                [
                    sys.executable, "-m", "gym_anything.remote.master",
                    "--host", "127.0.0.1", "--port", str(master_port), "--dev",
                ],
                cwd=repo_root,
                log_path=tmp_path / "master.log",
                env=proc_env,
            )
            worker = _ManagedProcess(
                [
                    sys.executable, "-m", "gym_anything.remote.worker",
                    "--host", "127.0.0.1", "--port", str(worker_port),
                    "--master-url", master_url,
                    "--max-envs", "2",
                    "--heartbeat-interval", "1",
                    "--advertise-host", "127.0.0.1",
                    "--must-support-runner", STRANGER_LOCATOR,
                ],
                cwd=repo_root,
                log_path=tmp_path / "worker.log",
                env=proc_env,
            )
            try:
                master.start()
                _eventually(
                    lambda: requests.get(f"{master_url}/health", timeout=1).status_code == 200,
                    description="master health endpoint",
                )
                worker.start()

                def _worker_advertises_stranger() -> bool:
                    worker.assert_running()
                    payload = requests.get(f"{master_url}/workers/list", timeout=2).json()
                    return any(
                        STRANGER_LOCATOR in (w.get("metadata") or {}).get("available_runners", [])
                        for w in payload.get("workers", [])
                    )

                _eventually(
                    _worker_advertises_stranger,
                    timeout=60.0,
                    description="worker advertising the stranger runner locator",
                )

                env = RemoteGymEnv.from_benchmark(
                    remote_url=master_url,
                    benchmark="stranger_master_world",
                    env_name="stranger_env",
                    task_id="deliver_t1",
                    timeout=60,
                    worker_reset_policy=None,
                )
                try:
                    obs = env.reset(seed=11)
                    self.assertIn("telemetry", obs)
                    obs, _, done, _ = env.step([{"action": "wait", "time": 5}])
                    self.assertFalse(done)
                    obs, _, done, _ = env.step([{"action": "deliver", "target": "parcel"}])
                    self.assertEqual(obs["telemetry"]["ticks"], 6)
                    obs, _reward, done, info = env.step([], mark_done=True)
                    self.assertTrue(done)
                    verifier = info.get("verifier") or {}
                    self.assertTrue(verifier.get("passed"), msg=f"verifier said: {verifier}")
                finally:
                    env.close()
            finally:
                worker.stop()
                master.stop()
                sys.path.remove(str(tmp_path / "pkgs"))
                sys.modules.pop("stranger_master_world", None)


if __name__ == "__main__":
    unittest.main()
