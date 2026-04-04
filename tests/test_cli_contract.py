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


if __name__ == "__main__":
    unittest.main()
