from __future__ import annotations

import unittest
from unittest import mock

from gym_anything.remote.worker_reset_policy import (
    BASELINE_SETUP_WORKER_RESET_POLICY,
    DEFAULT_WORKER_RESET_POLICY,
    InvalidResetPolicyError,
    apply_worker_reset_policy,
)


class _FakeRunner:
    def __init__(self) -> None:
        self.commands = []

    def exec(self, command: str) -> None:
        self.commands.append(command)


class _FakeEnv:
    def __init__(self) -> None:
        self._runner = _FakeRunner()


class WorkerResetPolicyTests(unittest.TestCase):
    def test_core_policy_is_noop(self) -> None:
        env = _FakeEnv()

        timings = apply_worker_reset_policy(env, DEFAULT_WORKER_RESET_POLICY)

        self.assertEqual(
            timings,
            {
                "apply_reset_policy": 0.0,
                "setup_env": 0.0,
                "disable_crash_reporter": 0.0,
            },
        )
        self.assertEqual(env._runner.commands, [])

    def test_baseline_setup_policy_runs_setup_and_crash_reporter_disable(self) -> None:
        env = _FakeEnv()

        with mock.patch("gym_anything.remote.worker_reset_policy.apply_post_reset_setup") as setup_env:
            timings = apply_worker_reset_policy(env, BASELINE_SETUP_WORKER_RESET_POLICY)

        setup_env.assert_called_once_with(env, setup_code="auto", steps=50)
        self.assertIn("setup_env", timings)
        self.assertIn("disable_crash_reporter", timings)
        self.assertIn("apply_reset_policy", timings)
        self.assertEqual(len(env._runner.commands), 4)

    def test_invalid_policy_raises(self) -> None:
        env = _FakeEnv()

        with self.assertRaises(InvalidResetPolicyError):
            apply_worker_reset_policy(env, "surprise-mode")


if __name__ == "__main__":
    unittest.main()
