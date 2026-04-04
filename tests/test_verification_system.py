from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from gym_anything.api import from_config
from gym_anything.verification import verify_environment_dir
from gym_anything.verification.pipeline import verify_task_pipeline


def _write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


class VerificationSystemTests(unittest.TestCase):
    def _create_minimal_env(self, root: Path) -> None:
        _write_json(
            root / "env.json",
            {
                "id": "test-env",
                "runner": "local",
                "observation": [{"type": "rgb_screen", "resolution": [640, 480]}],
                "action": [{"type": "mouse"}],
            },
        )

    def test_verify_environment_dir_succeeds_for_valid_task_layout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._create_minimal_env(root)
            task_dir = root / "tasks" / "demo"
            task_dir.mkdir(parents=True)
            _write_json(
                task_dir / "task.json",
                {
                    "id": "demo",
                    "description": "demo task",
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                    "hooks": {
                        "pre_task": "/workspace/tasks/demo/setup_task.sh",
                        "post_task": "/workspace/tasks/demo/export_result.sh",
                    },
                },
            )
            (task_dir / "setup_task.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (task_dir / "export_result.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (task_dir / "verifier.py").write_text(
                "def verify(traj, env_info, task_info):\n"
                "    return {'passed': False, 'score': 0}\n",
                encoding="utf-8",
            )

            summary = verify_environment_dir(root)

            self.assertTrue(summary.ok)
            self.assertEqual(summary.failed_records, 0)

    def test_verify_environment_dir_accepts_custom_hook_script_names(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._create_minimal_env(root)
            task_dir = root / "tasks" / "demo"
            task_dir.mkdir(parents=True)
            _write_json(
                task_dir / "task.json",
                {
                    "id": "demo",
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                    "hooks": {
                        "pre_task": "/workspace/tasks/demo/bootstrap_demo.sh",
                        "post_task": "/workspace/tasks/demo/finalize_demo.sh",
                    },
                },
            )
            (task_dir / "bootstrap_demo.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (task_dir / "finalize_demo.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (task_dir / "verifier.py").write_text(
                "def verify(traj, env_info, task_info):\n"
                "    return {'passed': True, 'score': 100}\n",
                encoding="utf-8",
            )

            summary = verify_environment_dir(root)

            self.assertTrue(summary.ok)
            self.assertEqual(summary.failed_records, 0)

    def test_verify_environment_dir_requires_exact_workspace_hook_target(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._create_minimal_env(root)

            other_task = root / "tasks" / "other"
            other_task.mkdir(parents=True)
            (other_task / "setup_task.ps1").write_text("# powershell\n", encoding="utf-8")
            (other_task / "export_result.ps1").write_text("# powershell\n", encoding="utf-8")

            task_dir = root / "tasks" / "demo"
            task_dir.mkdir(parents=True)
            _write_json(
                task_dir / "task.json",
                {
                    "id": "demo",
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                    "hooks": {
                        "pre_task": "powershell -File C:\\workspace\\tasks\\demo\\setup_task.ps1",
                        "post_task": "powershell -File C:\\workspace\\tasks\\demo\\export_result.ps1",
                    },
                },
            )
            (task_dir / "verifier.py").write_text(
                "def verify(traj, env_info, task_info):\n"
                "    return {'passed': True, 'score': 100}\n",
                encoding="utf-8",
            )

            summary = verify_environment_dir(root)

            self.assertFalse(summary.ok)
            messages = [issue.message for record in summary.records for issue in record.issues]
            self.assertTrue(any("tasks/demo/setup_task.ps1" in message for message in messages))

    def test_verify_environment_dir_resolves_mounted_hook_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            scripts_dir = root / "scripts"
            scripts_dir.mkdir(parents=True)
            (scripts_dir / "boot.sh").write_text("#!/bin/sh\n", encoding="utf-8")

            _write_json(
                root / "env.json",
                {
                    "id": "test-env",
                    "runner": "local",
                    "observation": [{"type": "rgb_screen", "resolution": [640, 480]}],
                    "action": [{"type": "mouse"}],
                    "mounts": [{"source": "scripts", "target": "/sdcard/scripts", "mode": "ro"}],
                    "hooks": {"post_start": "sh /sdcard/scripts/boot.sh"},
                },
            )

            task_dir = root / "tasks" / "demo"
            task_dir.mkdir(parents=True)
            _write_json(
                task_dir / "task.json",
                {
                    "id": "demo",
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                },
            )
            (task_dir / "verifier.py").write_text(
                "def verify(traj, env_info, task_info):\n"
                "    return {'passed': True, 'score': 100}\n",
                encoding="utf-8",
            )

            summary = verify_environment_dir(root)

            self.assertTrue(summary.ok)
            self.assertEqual(summary.failed_records, 0)

    def test_verify_environment_dir_resolves_windows_workspace_alias_for_mounts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            task_dir = root / "tasks" / "demo"
            task_dir.mkdir(parents=True)
            (task_dir / "setup_task.ps1").write_text("# powershell\n", encoding="utf-8")
            (task_dir / "export_result.ps1").write_text("# powershell\n", encoding="utf-8")

            _write_json(
                root / "env.json",
                {
                    "id": "test-env",
                    "runner": "local",
                    "observation": [{"type": "rgb_screen", "resolution": [640, 480]}],
                    "action": [{"type": "mouse"}],
                    "mounts": [{"source": "tasks", "target": "/workspace/tasks", "mode": "ro"}],
                },
            )
            _write_json(
                task_dir / "task.json",
                {
                    "id": "demo",
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                    "hooks": {
                        "pre_task": "powershell -File C:\\workspace\\tasks\\demo\\setup_task.ps1",
                        "post_task": "powershell -File C:\\workspace\\tasks\\demo\\export_result.ps1",
                    },
                },
            )
            (task_dir / "verifier.py").write_text(
                "def verify(traj, env_info, task_info):\n"
                "    return {'passed': True, 'score': 100}\n",
                encoding="utf-8",
            )

            summary = verify_environment_dir(root)

            self.assertTrue(summary.ok)
            self.assertEqual(summary.failed_records, 0)

    def test_verify_environment_dir_rejects_unsupported_success_mode(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._create_minimal_env(root)
            task_dir = root / "tasks" / "demo"
            task_dir.mkdir(parents=True)
            _write_json(
                task_dir / "task.json",
                {
                    "id": "demo",
                    "success": {"mode": "llm_rubric", "spec": {}},
                },
            )

            summary = verify_environment_dir(root)

            self.assertFalse(summary.ok)
            self.assertEqual(summary.failed_records, 1)

    def test_verify_environment_dir_detects_missing_verifier_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._create_minimal_env(root)
            task_dir = root / "tasks" / "demo"
            task_dir.mkdir(parents=True)
            _write_json(
                task_dir / "task.json",
                {
                    "id": "demo",
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                },
            )
            (task_dir / "verifier.py").write_text(
                "import definitely_missing_dependency\n"
                "def verify(traj, env_info, task_info):\n"
                "    return {'passed': False, 'score': 0}\n",
                encoding="utf-8",
            )

            summary = verify_environment_dir(root)

            self.assertFalse(summary.ok)
            messages = [issue.message for record in summary.records for issue in record.issues]
            self.assertTrue(any("missing modules" in message for message in messages))

    def test_verify_environment_dir_allows_env_local_verifier_utils(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._create_minimal_env(root)
            utils_dir = root / "utils"
            utils_dir.mkdir(parents=True)
            (utils_dir / "helper_module.py").write_text(
                "def meaning_of_life():\n"
                "    return 42\n",
                encoding="utf-8",
            )
            task_dir = root / "tasks" / "demo"
            task_dir.mkdir(parents=True)
            _write_json(
                task_dir / "task.json",
                {
                    "id": "demo",
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                },
            )
            (task_dir / "verifier.py").write_text(
                "from helper_module import meaning_of_life\n"
                "def verify(traj, env_info, task_info):\n"
                "    return {'passed': meaning_of_life() == 42, 'score': 100}\n",
                encoding="utf-8",
            )

            summary = verify_environment_dir(root)

            self.assertTrue(summary.ok)
            self.assertEqual(summary.failed_records, 0)

    def test_verify_task_pipeline_runs_existing_verifier_flow(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._create_minimal_env(root)
            task_dir = root / "tasks" / "demo"
            task_dir.mkdir(parents=True)
            _write_json(
                task_dir / "task.json",
                {
                    "id": "demo",
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                },
            )
            (task_dir / "verifier.py").write_text(
                "def verify(traj, env_info, task_info):\n"
                "    return {'passed': False, 'score': 0, 'feedback': 'expected no-op fail'}\n",
                encoding="utf-8",
            )

            with mock.patch("gym_anything.env.time.sleep", lambda *_args, **_kwargs: None):
                result = verify_task_pipeline(root, "demo")

            self.assertTrue(result.ok)
            self.assertEqual(result.stage, "verifier")
            self.assertIsNotNone(result.verifier)
            self.assertFalse(result.verifier["passed"])

    def test_local_runner_hint_is_honored(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._create_minimal_env(root)
            env = from_config(root)
            try:
                self.assertEqual(env.runner_name, "LocalRunner")
            finally:
                env.close()


if __name__ == "__main__":
    unittest.main()
