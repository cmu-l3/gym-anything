from __future__ import annotations

import unittest
from pathlib import Path
from unittest import mock

from gym_anything.remote.client import RemoteGymEnv


class RemoteClientResetPolicyTests(unittest.TestCase):
    def _make_env(self, worker_reset_policy="core") -> RemoteGymEnv:
        env = RemoteGymEnv.__new__(RemoteGymEnv)
        env.remote_url = "http://localhost:5000"
        env.timeout = 300
        env.env_id = "env-123"
        env._episode_dir = None
        env._cache_dir = Path("/tmp")
        env._closed = False
        env.worker_reset_policy = worker_reset_policy
        return env

    def test_reset_sends_core_policy_by_default(self) -> None:
        env = self._make_env()
        response = mock.Mock()
        response.json.return_value = {"observation": {"screen": {"path": "frame.png"}}}

        with mock.patch.object(env, "_request", return_value=response) as request_mock:
            obs = env.reset(seed=7, use_cache=True, cache_level="post_start", use_savevm=True)

        self.assertEqual(obs, {"screen": {"path": "frame.png"}})
        self.assertEqual(
            request_mock.call_args_list[0],
            mock.call(
                "POST",
                "/envs/env-123/reset",
                json={
                    "seed": 7,
                    "use_cache": True,
                    "cache_level": "post_start",
                    "use_savevm": True,
                    "post_reset_policy": "core",
                },
            ),
        )

    def test_reset_can_omit_policy_override(self) -> None:
        env = self._make_env(worker_reset_policy=None)
        response = mock.Mock()
        response.json.return_value = {"observation": {"screen": {"path": "frame.png"}}}

        with mock.patch.object(env, "_request", return_value=response) as request_mock:
            env.reset()

        self.assertIsNone(request_mock.call_args_list[0].kwargs["json"]["post_reset_policy"])


if __name__ == "__main__":
    unittest.main()
