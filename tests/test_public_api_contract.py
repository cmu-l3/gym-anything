from __future__ import annotations

import inspect
import json
import unittest
from pathlib import Path

from gym_anything.env import GymAnythingEnv
from gym_anything.remote.client import RemoteGymEnv
from gym_anything.specs import TaskSpec
from gym_anything import (
    SessionInfo,
    get_runner_compatibility,
    get_runner_compatibility_matrix,
)


class TaskSpecCompatibilityTests(unittest.TestCase):
    def test_common_top_level_task_metadata_is_preserved(self) -> None:
        data = {
            "id": "demo-task",
            "env_id": "demo-env",
            "version": "2.0",
            "description": "Demo task description",
            "name": "Demo Task",
            "difficulty": "easy",
            "tags": ["demo", "compat"],
            "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
            "metadata": {"owner": "tests"},
            "estimated_time_minutes": 5,
        }

        spec = TaskSpec.from_dict(data)

        self.assertEqual(spec.version, "2.0")
        self.assertEqual(spec.description, "Demo task description")
        self.assertEqual(spec.name, "Demo Task")
        self.assertEqual(spec.tags, ["demo", "compat"])
        self.assertEqual(spec.metadata, {"owner": "tests"})
        self.assertEqual(spec.extras, {"estimated_time_minutes": 5})

    def test_real_corpus_task_description_is_available(self) -> None:
        task_path = Path(
            "benchmarks/cua_world/environments/zotero_env/tasks/update_preprints_to_proceedings/task.json"
        )
        data = json.loads(task_path.read_text(encoding="utf-8"))

        spec = TaskSpec.from_dict(data)

        self.assertEqual(spec.description, data["description"])
        self.assertEqual(spec.version, data["version"])


class PublicApiContractTests(unittest.TestCase):
    def test_env_exposes_public_capture_observation(self) -> None:
        self.assertTrue(callable(getattr(GymAnythingEnv, "capture_observation", None)))

    def test_env_exposes_public_episode_dir_property(self) -> None:
        self.assertIsInstance(getattr(GymAnythingEnv, "episode_dir", None), property)

    def test_env_exposes_public_roots_properties(self) -> None:
        self.assertIsInstance(getattr(GymAnythingEnv, "env_root", None), property)
        self.assertIsInstance(getattr(GymAnythingEnv, "task_root", None), property)

    def test_env_exposes_public_episode_limit_override(self) -> None:
        self.assertTrue(callable(getattr(GymAnythingEnv, "set_episode_limits", None)))

    def test_env_exposes_public_compatibility_profile(self) -> None:
        self.assertTrue(callable(getattr(GymAnythingEnv, "get_compatibility_profile", None)))

    def test_env_exposes_public_session_info(self) -> None:
        self.assertTrue(callable(getattr(GymAnythingEnv, "get_session_info", None)))

    def test_env_exposes_public_post_reset_setup(self) -> None:
        self.assertTrue(callable(getattr(GymAnythingEnv, "apply_post_reset_setup", None)))

    def test_remote_reset_signature_matches_supported_local_reset_args(self) -> None:
        params = inspect.signature(RemoteGymEnv.reset).parameters
        self.assertIn("cache_level", params)
        self.assertIn("use_savevm", params)

    def test_remote_exposes_public_capture_observation(self) -> None:
        self.assertTrue(callable(getattr(RemoteGymEnv, "capture_observation", None)))

    def test_remote_exposes_public_episode_dir_property(self) -> None:
        self.assertIsInstance(getattr(RemoteGymEnv, "episode_dir", None), property)

    def test_remote_exposes_public_session_info(self) -> None:
        self.assertTrue(callable(getattr(RemoteGymEnv, "get_session_info", None)))

    def test_remote_from_config_exposes_worker_reset_policy_override(self) -> None:
        params = inspect.signature(RemoteGymEnv.from_config).parameters
        self.assertIn("worker_reset_policy", params)

    def test_public_runner_compatibility_helpers_exist(self) -> None:
        self.assertTrue(callable(get_runner_compatibility))
        self.assertTrue(callable(get_runner_compatibility_matrix))

    def test_session_info_dataclass_is_exported(self) -> None:
        self.assertTrue(callable(SessionInfo))


if __name__ == "__main__":
    unittest.main()
