from __future__ import annotations

import unittest
from argparse import Namespace
from pathlib import Path
from unittest import mock

from gym_anything import cli


class CliContractTests(unittest.TestCase):
    def test_short_environment_name_resolves_to_cua_world_environment(self) -> None:
        resolved = Path(cli._resolve_env_dir("moodle"))
        self.assertEqual(resolved, Path("benchmarks/cua_world/environments/moodle_env"))

    def test_interactive_run_accepts_short_environment_name(self) -> None:
        env = mock.Mock()
        reporter = mock.MagicMock()
        args = Namespace(
            env_dir="moodle",
            task=None,
            interactive=True,
            seed=42,
            open_vnc=False,
        )

        with mock.patch.object(cli, "_pick_random_task", return_value="demo_task"), \
             mock.patch.object(cli, "from_config", return_value=env) as mock_from_config, \
             mock.patch("gym_anything.tui.progress.create_reporter", return_value=reporter), \
             mock.patch("gym_anything.tui.session.InteractiveSession") as mock_session_cls:
            result = cli.cmd_run(args)

        self.assertEqual(result, 0)
        mock_from_config.assert_called_once_with(
            "benchmarks/cua_world/environments/moodle_env",
            task_id="demo_task",
        )
        env.set_reporter.assert_called_once_with(reporter)
        env.reset.assert_called_once_with(seed=42)
        reporter.define_stages.assert_called_once()
        mock_session_cls.assert_called_once_with(env, auto_open_vnc=False)
        mock_session_cls.return_value.run.assert_called_once()

    def test_benchmark_batch_respects_parallel_max_tasks_and_remote_flags(self) -> None:
        args = Namespace(
            env_dir="demo_env",
            split="test",
            surface="raw",
            agent="FakeAgent",
            seed=7,
            cache_level="post_start",
            steps=1,
            model="demo-model",
            exp_name="demo-exp",
            use_cache=True,
            use_savevm=False,
            temperature=None,
            remote_url="http://127.0.0.1:5800",
            remote_timeout=123,
            remote_worker_reset_policy="core",
            agent_arg=[],
            parallel=2,
            max_tasks=3,
            verifier_mode=None,
            vlm_checklist_model=None,
            vlm_checklist_backend=None,
            vlm_checklist_base_url=None,
            vlm_checklist_temperature=None,
            vlm_checklist_top_p=None,
            vlm_checklist_max_tokens=None,
            vlm_checklist_max_frames=None,
            vlm_checklist_completion_threshold=None,
            vlm_checklist_integrity_threshold=None,
        )

        completed = mock.Mock(returncode=0)
        with mock.patch("gym_anything.registry.resolve_environment_key", return_value="demo_env"), \
             mock.patch(
                 "gym_anything.registry.get_tasks_for_environment",
                 return_value=["task_a", "task_b", "task_c", "task_d"],
             ), \
             mock.patch.object(cli.subprocess, "run", return_value=completed) as run_mock:
            result = cli._run_benchmark_batch(args)

        self.assertEqual(result, 0)
        self.assertEqual(run_mock.call_count, 3)
        commands = [call.args[0] for call in run_mock.call_args_list]
        command_text = "\n".join(" ".join(command) for command in commands)
        self.assertIn("--task task_a", command_text)
        self.assertIn("--task task_b", command_text)
        self.assertIn("--task task_c", command_text)
        self.assertNotIn("--task task_d", command_text)
        for command in commands:
            self.assertIn("--remote-url", command)
            self.assertIn("http://127.0.0.1:5800", command)
            self.assertIn("--remote-timeout", command)
            self.assertIn("123", command)
            self.assertIn("--remote-worker-reset-policy", command)
            self.assertIn("core", command)


if __name__ == "__main__":
    unittest.main()
