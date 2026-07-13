from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from gym_anything.api import from_config
from gym_anything.contracts import RunnerRuntimeInfo
from gym_anything.env import _require_hook_success
from gym_anything.specs import EnvSpec, TaskSpec
from gym_anything.verification import verify_environment_dir
from gym_anything.verification.pipeline import verify_task_pipeline
from gym_anything.verification.runner import VerifierRunner


def _write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


_VERIFIER_ENV_DEFAULTS = {
    "GYM_ANYTHING_VERIFIER_MODE": "",
    "GYM_ANYTHING_VLM_CHECKLIST_MODEL": "",
    "GYM_ANYTHING_VLM_CHECKLIST_BACKEND": "",
    "GYM_ANYTHING_VLM_CHECKLIST_BASE_URL": "",
    "GYM_ANYTHING_VLM_CHECKLIST_API_KEY": "",
    "GYM_ANYTHING_VLM_CHECKLIST_CHECKLIST": "",
    "GYM_ANYTHING_VLM_CHECKLIST_CHECKLIST_PATH": "",
    "GYM_ANYTHING_VLM_CHECKLIST_MAX_RETRIES": "",
    "GYM_ANYTHING_VLM_CHECKLIST_TEMPERATURE": "",
    "GYM_ANYTHING_VLM_CHECKLIST_TOP_P": "",
    "GYM_ANYTHING_VLM_CHECKLIST_MAX_TOKENS": "",
    "GYM_ANYTHING_VLM_CHECKLIST_MAX_FRAMES": "",
    "GYM_ANYTHING_VLM_CHECKLIST_FRAME_STRATEGY": "",
    "GYM_ANYTHING_VLM_CHECKLIST_COMPLETION_THRESHOLD": "",
    "GYM_ANYTHING_VLM_CHECKLIST_INTEGRITY_THRESHOLD": "",
}


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

    def test_failed_task_setup_hook_is_fatal_and_includes_its_log(self) -> None:
        runner = mock.Mock()
        runner.exec_capture.return_value = "setup exploded\n"

        with self.assertRaisesRegex(
            RuntimeError,
            "(?s)pre_task hook exited with code 17.*setup exploded",
        ):
            _require_hook_success(
                runner,
                "pre_task hook",
                17,
                "/tmp/task_pre_task.log",
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

    def test_verify_environment_dir_accepts_vlm_checklist_mode_with_checklist(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._create_minimal_env(root)
            task_dir = root / "tasks" / "demo"
            task_dir.mkdir(parents=True)
            _write_json(
                task_dir / "task.json",
                {
                    "id": "demo",
                    "success": {"mode": "vlm_checklist", "spec": {}},
                },
            )
            _write_json(
                task_dir / "vlm_checklist.json",
                {
                    "task_completion": [{"id": "done", "points": 100}],
                    "integrity": [{"id": "honest"}],
                },
            )

            summary = verify_environment_dir(root)

            self.assertTrue(summary.ok)
            self.assertEqual(summary.failed_records, 0)

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

    def test_program_verifier_receives_complete_runner_runtime_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            task_dir = root / "tasks" / "demo"
            episode_dir = root / "episode"
            task_dir.mkdir(parents=True)
            episode_dir.mkdir()
            (task_dir / "verifier.py").write_text(
                "def verify(traj, env_info, task_info):\n"
                "    return {\n"
                "        'passed': True, 'score': 100,\n"
                "        'seen_ssh_port': env_info.get('ssh_port'),\n"
                "        'seen_ssh_user': env_info.get('ssh_user'),\n"
                "        'seen_vnc_port': env_info.get('vnc_port'),\n"
                "    }\n",
                encoding="utf-8",
            )
            env_spec = EnvSpec.from_dict({
                "id": "test-env",
                "runner": "local",
                "observation": [{"type": "rgb_screen", "resolution": [640, 480]}],
                "action": [{"type": "mouse"}],
            })
            task_spec = TaskSpec.from_dict({
                "id": "demo",
                "success": {
                    "mode": "program",
                    "spec": {"program": "verifier.py::verify"},
                },
            })
            runner = mock.Mock()
            runner.get_runtime_info.return_value = RunnerRuntimeInfo(
                platform_family="linux",
                ssh_port=2222,
                ssh_user="user",
                ssh_password="password",
                vnc_port=5901,
            )

            result = VerifierRunner().evaluate(
                runner=runner,
                env_spec=env_spec,
                task_spec=task_spec,
                episode_dir=episode_dir,
                env_root=root,
                task_root=task_dir,
            )

            self.assertTrue(result["passed"])
            self.assertEqual(result["seen_ssh_port"], 2222)
            self.assertEqual(result["seen_ssh_user"], "user")
            self.assertEqual(result["seen_vnc_port"], 5901)

    def test_vlm_checklist_verifier_scores_trajectory_with_mocked_vlm(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            task_dir = root / "tasks" / "demo"
            episode_dir = root / "episode"
            task_dir.mkdir(parents=True)
            episode_dir.mkdir()
            (episode_dir / "frame_00000.png").write_bytes(b"fake-png")
            _write_json(
                task_dir / "vlm_checklist.json",
                {
                    "task_completion": [
                        {"id": "open_app", "points": 60},
                        {"id": "finish_output", "points": 40},
                    ],
                    "integrity": [{"id": "used_gui"}],
                },
            )
            env_spec = EnvSpec.from_dict(
                {
                    "id": "test-env",
                    "runner": "local",
                    "observation": [{"type": "rgb_screen", "resolution": [640, 480]}],
                    "action": [{"type": "mouse"}],
                }
            )
            task_spec = TaskSpec.from_dict(
                {
                    "id": "demo",
                    "description": "Finish the output in the app.",
                    "success": {
                        "mode": "vlm_checklist",
                        "spec": {"model": "judge-model", "completion_threshold": 80},
                    },
                }
            )
            vlm_response = {
                "success": True,
                "response": "{}",
                "parsed": {
                    "task_completion": [
                        {"id": "open_app", "verdict": "pass", "confidence": 1.0, "evidence": "open"},
                        {
                            "id": "finish_output",
                            "verdict": "partial",
                            "confidence": 0.8,
                            "evidence": "some output",
                        },
                    ],
                    "integrity": [
                        {"id": "used_gui", "verdict": "pass", "confidence": 1.0, "evidence": "gui"}
                    ],
                    "overall_reasoning": "The agent made enough visible progress.",
                },
            }

            with mock.patch.dict(os.environ, _VERIFIER_ENV_DEFAULTS, clear=False), \
                 mock.patch("gym_anything.verification.vlm_checklist.query_vlm", return_value=vlm_response) as query:
                result = VerifierRunner().evaluate(
                    runner=mock.Mock(),
                    env_spec=env_spec,
                    task_spec=task_spec,
                    episode_dir=episode_dir,
                    env_root=root,
                    task_root=task_dir,
                )

            self.assertTrue(result["passed"])
            self.assertEqual(result["mode"], "vlm_checklist")
            self.assertEqual(result["score"], 80.0)
            self.assertEqual(result["config"]["model"], "judge-model")
            self.assertEqual(result["scores"]["integrity_pass_rate"], "1/1")
            query.assert_called_once()
            self.assertEqual(query.call_args.kwargs["images"], [str(episode_dir / "frame_00000.png")])

    def test_verifier_mode_env_overrides_task_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            task_dir = root / "tasks" / "demo"
            episode_dir = root / "episode"
            task_dir.mkdir(parents=True)
            episode_dir.mkdir()
            (episode_dir / "frame_00000.png").write_bytes(b"fake-png")
            _write_json(
                task_dir / "vlm_checklist.json",
                {
                    "task_completion": [{"id": "done", "points": 100}],
                    "integrity": [],
                },
            )
            env_spec = EnvSpec.from_dict(
                {
                    "id": "test-env",
                    "runner": "local",
                    "observation": [{"type": "rgb_screen", "resolution": [640, 480]}],
                    "action": [{"type": "mouse"}],
                }
            )
            task_spec = TaskSpec.from_dict(
                {
                    "id": "demo",
                    "description": "Do the thing.",
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                }
            )
            env = {
                **_VERIFIER_ENV_DEFAULTS,
                "GYM_ANYTHING_VERIFIER_MODE": "vlm_checklist",
                "GYM_ANYTHING_VLM_CHECKLIST_MODEL": "env-judge",
            }
            vlm_response = {
                "success": True,
                "response": "{}",
                "parsed": {
                    "task_completion": [
                        {"id": "done", "verdict": "pass", "confidence": 1.0, "evidence": "done"}
                    ],
                    "integrity": [],
                },
            }

            with mock.patch.dict(os.environ, env, clear=False), \
                 mock.patch("gym_anything.verification.vlm_checklist.query_vlm", return_value=vlm_response):
                result = VerifierRunner().evaluate(
                    runner=mock.Mock(),
                    env_spec=env_spec,
                    task_spec=task_spec,
                    episode_dir=episode_dir,
                    env_root=root,
                    task_root=task_dir,
                )

            self.assertTrue(result["passed"])
            self.assertEqual(result["mode"], "vlm_checklist")
            self.assertEqual(result["mode_source"], "env")
            self.assertEqual(result["task_mode"], "program")
            self.assertEqual(result["config"]["model"], "env-judge")

    def test_verifier_env_payload_overrides_worker_env(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            task_dir = root / "tasks" / "demo"
            episode_dir = root / "episode"
            task_dir.mkdir(parents=True)
            episode_dir.mkdir()
            (episode_dir / "frame_00000.png").write_bytes(b"fake-png")
            _write_json(
                task_dir / "vlm_checklist.json",
                {
                    "task_completion": [{"id": "done", "points": 100}],
                    "integrity": [],
                },
            )
            env_spec = EnvSpec.from_dict(
                {
                    "id": "test-env",
                    "runner": "local",
                    "observation": [{"type": "rgb_screen", "resolution": [640, 480]}],
                    "action": [{"type": "mouse"}],
                }
            )
            task_spec = TaskSpec.from_dict(
                {
                    "id": "demo",
                    "description": "Do the thing.",
                    "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
                }
            )
            verifier_env = {
                "GYM_ANYTHING_VERIFIER_MODE": "vlm_checklist",
                "GYM_ANYTHING_VLM_CHECKLIST_BACKEND": "gemini",
                "GYM_ANYTHING_VLM_CHECKLIST_MODEL": "request-judge",
                "GEMINI_API_KEY": "request-secret",
                "VLM_TIMEOUT": "123",
            }
            worker_env = {
                **_VERIFIER_ENV_DEFAULTS,
                "GYM_ANYTHING_VERIFIER_MODE": "program",
                "GYM_ANYTHING_VLM_CHECKLIST_MODEL": "worker-judge",
            }
            vlm_response = {
                "success": True,
                "response": "{}",
                "parsed": {
                    "task_completion": [
                        {"id": "done", "verdict": "pass", "confidence": 1.0, "evidence": "done"}
                    ],
                    "integrity": [],
                },
            }

            with mock.patch.dict(os.environ, worker_env, clear=False), \
                 mock.patch("gym_anything.verification.vlm_checklist.query_vlm", return_value=vlm_response) as query:
                result = VerifierRunner().evaluate(
                    runner=mock.Mock(),
                    env_spec=env_spec,
                    task_spec=task_spec,
                    episode_dir=episode_dir,
                    env_root=root,
                    task_root=task_dir,
                    verifier_env=verifier_env,
                )

            self.assertTrue(result["passed"])
            self.assertEqual(result["mode"], "vlm_checklist")
            self.assertEqual(result["mode_source"], "env")
            self.assertEqual(result["config"]["model"], "request-judge")
            self.assertEqual(query.call_args.kwargs["config"]["backend"], "gemini")
            self.assertEqual(query.call_args.kwargs["config"]["api_key"], "request-secret")
            self.assertEqual(query.call_args.kwargs["config"]["timeout"], 123)

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
