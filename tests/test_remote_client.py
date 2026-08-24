from __future__ import annotations

import os
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
        env._max_steps_override = None
        env._timeout_sec_override = None
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

    def test_set_episode_limits_posts_to_remote_env(self) -> None:
        env = self._make_env()
        response = mock.Mock()
        response.json.return_value = {"status": "updated", "max_steps": 3, "timeout_sec": 120}

        with mock.patch.object(env, "_request", return_value=response) as request_mock:
            env.set_episode_limits(max_steps=3, timeout_sec=120)

        request_mock.assert_called_once_with(
            "POST",
            "/envs/env-123/episode_limits",
            json={"max_steps": 3, "timeout_sec": 120},
        )
        self.assertEqual(env.max_steps, 3)
        self.assertEqual(env.timeout_sec, 120)

    def test_step_sends_deferred_capture_controls(self) -> None:
        env = self._make_env()
        response = mock.Mock()
        response.json.return_value = {
            "observation": {},
            "reward": 0.0,
            "done": False,
            "info": {"step": 0},
        }

        with mock.patch.object(env, "_request", return_value=response) as request_mock:
            result = env.step(
                [{"mouse": {"move": [1, 2]}}],
                capture_observation=False,
                settle_after_actions=False,
            )

        self.assertEqual(result[0], {})
        self.assertEqual(
            request_mock.call_args.kwargs["json"],
            {
                "actions": [{"mouse": {"move": [1, 2]}}],
                "wait_between_actions": 0.2,
                "mark_done": False,
                "capture_observation": False,
                "settle_after_actions": False,
            },
        )

    def test_create_remote_env_sends_verifier_overrides(self) -> None:
        response = mock.Mock()
        response.json.return_value = {"env_id": "env-123"}
        verifier_env = {
            "GYM_ANYTHING_VERIFIER_MODE": "task",
            "GYM_ANYTHING_VLM_CHECKLIST_BACKEND": "gemini",
            "GYM_ANYTHING_VLM_CHECKLIST_MODEL": "gemini-3-flash-preview",
            "VLM_TIMEOUT": "240",
            "GEMINI_API_KEY": "secret-key",
        }

        with mock.patch.dict(os.environ, verifier_env, clear=True), \
             mock.patch("gym_anything.remote.client.requests.request", return_value=response) as post, \
             mock.patch.object(RemoteGymEnv, "_setup_cache"):
            RemoteGymEnv.from_config(
                remote_url="http://localhost:5000",
                env_dir="demo-env",
                task_id="demo-task",
            )

        response.raise_for_status.assert_called_once()
        self.assertEqual(post.call_args.args[0], "POST")
        payload = post.call_args.kwargs["json"]
        self.assertEqual(payload["env_dir"], "demo-env")
        self.assertEqual(payload["task_id"], "demo-task")
        self.assertEqual(payload["verifier_env"], verifier_env)
        self.assertNotIn("verifier_env", payload.get("metadata", {}))

    def test_create_remote_env_sends_fast_io(self) -> None:
        response = mock.Mock()
        response.json.return_value = {"env_id": "env-123"}

        with mock.patch("gym_anything.remote.client.requests.request", return_value=response) as post, \
             mock.patch.object(RemoteGymEnv, "_setup_cache"):
            RemoteGymEnv.from_config(
                remote_url="http://localhost:5000",
                env_dir="demo-env",
                task_id="demo-task",
                fast_io=True,
            )

        payload = post.call_args.kwargs["json"]
        self.assertTrue(payload["fast_io"])

    def test_create_remote_env_sends_runtime_overrides(self) -> None:
        response = mock.Mock()
        response.json.return_value = {"env_id": "env-123"}
        overrides = {"runner_options": {"time_mode": "live"}}

        with mock.patch("gym_anything.remote.client.requests.request", return_value=response) as post, \
             mock.patch.object(RemoteGymEnv, "_setup_cache"):
            RemoteGymEnv.from_config(
                remote_url="http://localhost:5000",
                env_dir="demo-env",
                task_id="demo-task",
                overrides=overrides,
            )

        self.assertEqual(post.call_args.kwargs["json"]["overrides"], overrides)

    def test_create_by_benchmark_sends_runtime_overrides(self) -> None:
        response = mock.Mock()
        response.json.return_value = {"env_id": "env-123"}
        overrides = {
            "runner_options": {
                "time_mode": "live",
                "observation_window_ms": 0,
                "frames_per_observation": 1,
            }
        }

        with mock.patch(
            "gym_anything.remote.client.requests.request", return_value=response
        ) as post, mock.patch.object(RemoteGymEnv, "_setup_cache"), mock.patch(
            "gym_anything.registry.resolve_environment_dir",
            side_effect=LookupError("client benchmark is not installed in this unit test"),
        ):
            RemoteGymEnv.from_benchmark(
                remote_url="http://localhost:5000",
                benchmark="demo-benchmark",
                env_name="demo-env",
                task_id="demo-task",
                overrides=overrides,
            )

        payload = post.call_args.kwargs["json"]
        self.assertEqual(payload["benchmark"], "demo-benchmark")
        self.assertEqual(payload["env_name"], "demo-env")
        self.assertEqual(payload["task_id"], "demo-task")
        self.assertEqual(payload["overrides"], overrides)

    def test_worker_applies_runtime_overrides_to_from_config(self) -> None:
        from gym_anything.remote import worker

        manager = worker.EnvironmentManager()
        fake_env = object()
        overrides = {"runner_options": {"time_mode": "paused"}}
        with mock.patch.object(worker, "from_config", return_value=fake_env) as make_env:
            env_id = manager.create_environment(
                env_spec_dict={},
                env_dir="demo-env",
                task_id="demo-task",
                fast_io=True,
                overrides=overrides,
            )
        try:
            make_env.assert_called_once_with(
                "demo-env",
                task_id="demo-task",
                overrides=overrides,
                fast_io=True,
            )
            self.assertIs(worker.env_registry[env_id]["env"], fake_env)
        finally:
            with worker.registry_lock:
                worker.env_registry.pop(env_id, None)

    def test_worker_serializes_fast_io_image_observation(self) -> None:
        from PIL import Image

        from gym_anything.remote.worker import serialize_observation, serialize_response

        image = Image.new("RGB", (2, 3), "white")
        serialized = serialize_observation({"screen": {"image": image, "format": "pil"}})

        self.assertNotIn("image", serialized["screen"])
        self.assertEqual(serialized["screen"]["format"], "png")
        self.assertEqual(serialized["screen"]["resolution"], [2, 3])
        self.assertIn("png_b64", serialized["screen"])
        self.assertEqual(serialize_response(image)["resolution"], [2, 3])


if __name__ == "__main__":
    unittest.main()
