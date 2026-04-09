"""Unit tests for gym_anything.config.loading private and public helpers.

Covers:
- _resolve_security_runtime — with and without secrets_ref
- _load_envspec — from EnvSpec instance, dict, path (YAML / JSON), with/without base preset
- _load_taskspec — from None, TaskSpec instance, dict, path (YAML / JSON)
- make — TypeError on bad input type, integration path using dicts (GymAnythingEnv patched)
- from_config — FileNotFoundError paths, ambiguous task resolution
"""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from gym_anything.config.loading import (
    _load_envspec,
    _load_taskspec,
    _resolve_security_runtime,
    make,
    from_config,
)
from gym_anything.specs import EnvSpec, TaskSpec


# ---------------------------------------------------------------------------
# Minimal valid spec dicts
# ---------------------------------------------------------------------------

_MINIMAL_ENV_DICT = {
    "id": "test-env",
    "runner": "local",
    "observation": [{"type": "rgb_screen"}],
    "action": [{"type": "mouse"}],
}

_MINIMAL_TASK_DICT = {
    "id": "test-task",
    "env_id": "test-env",
}


def _make_env_spec(**kwargs) -> EnvSpec:
    d = dict(_MINIMAL_ENV_DICT, **kwargs)
    return EnvSpec.from_dict(d)


def _make_task_spec(**kwargs) -> TaskSpec:
    d = dict(_MINIMAL_TASK_DICT, **kwargs)
    return TaskSpec.from_dict(d)


# ---------------------------------------------------------------------------
# _resolve_security_runtime
# ---------------------------------------------------------------------------

class ResolveSecurityRuntimeTests(unittest.TestCase):
    def test_no_secrets_ref_returns_spec_unchanged(self) -> None:
        spec = _make_env_spec()
        self.assertIsNone(spec.security.secrets_ref)
        result = _resolve_security_runtime(spec)
        self.assertIs(result, spec)

    def test_with_secrets_ref_calls_load_secret_env(self) -> None:
        spec = _make_env_spec()
        spec.security.secrets_ref = "some.env"
        fake_env = {"MY_KEY": "my_value"}
        with mock.patch(
            "gym_anything.config.loading.load_secret_env",
            return_value=fake_env,
        ) as mock_load:
            result = _resolve_security_runtime(spec, base_dir=Path("/tmp"))
        mock_load.assert_called_once_with("some.env", base_dir=Path("/tmp"))
        self.assertEqual(result.security.resolved_env, fake_env)

    def test_with_secrets_ref_no_base_dir(self) -> None:
        spec = _make_env_spec()
        spec.security.secrets_ref = "secret.env"
        with mock.patch(
            "gym_anything.config.loading.load_secret_env",
            return_value={},
        ):
            result = _resolve_security_runtime(spec)
        self.assertEqual(result.security.resolved_env, {})


# ---------------------------------------------------------------------------
# _load_envspec
# ---------------------------------------------------------------------------

class LoadEnvSpecFromInstanceTests(unittest.TestCase):
    def test_envspec_instance_returned_directly(self) -> None:
        spec = _make_env_spec()
        result = _load_envspec(spec)
        self.assertIsInstance(result, EnvSpec)
        self.assertEqual(result.id, "test-env")

    def test_envspec_instance_resolves_security(self) -> None:
        spec = _make_env_spec()
        spec.security.secrets_ref = "s.env"
        with mock.patch(
            "gym_anything.config.loading.load_secret_env",
            return_value={"K": "V"},
        ):
            result = _load_envspec(spec)
        self.assertEqual(result.security.resolved_env, {"K": "V"})


class LoadEnvSpecFromDictTests(unittest.TestCase):
    def test_plain_dict_loads(self) -> None:
        result = _load_envspec(_MINIMAL_ENV_DICT)
        self.assertIsInstance(result, EnvSpec)
        self.assertEqual(result.id, "test-env")

    def test_dict_with_unknown_base_raises(self) -> None:
        d = dict(_MINIMAL_ENV_DICT, base="nonexistent-preset")
        with self.assertRaises(ValueError):
            _load_envspec(d)

    def test_dict_with_valid_base_merges(self) -> None:
        # x11-lite is a known preset — merging should succeed
        d = dict(_MINIMAL_ENV_DICT, base="x11-lite")
        result = _load_envspec(d)
        self.assertIsInstance(result, EnvSpec)
        # The id from the override dict takes priority
        self.assertEqual(result.id, "test-env")


class LoadEnvSpecFromPathTests(unittest.TestCase):
    def test_json_file_loads(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "env.json"
            p.write_text(json.dumps(_MINIMAL_ENV_DICT), encoding="utf-8")
            result = _load_envspec(str(p))
        self.assertIsInstance(result, EnvSpec)
        self.assertEqual(result.id, "test-env")

    def test_yaml_file_loads(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "env.yaml"
            p.write_text(
                "id: test-env\nrunner: local\nobservation:\n  - type: rgb_screen\naction:\n  - type: mouse\n",
                encoding="utf-8",
            )
            result = _load_envspec(p)
        self.assertIsInstance(result, EnvSpec)
        self.assertEqual(result.id, "test-env")

    def test_path_with_base_preset_merges(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "env.json"
            d = dict(_MINIMAL_ENV_DICT, base="x11-lite")
            p.write_text(json.dumps(d), encoding="utf-8")
            result = _load_envspec(p)
        self.assertIsInstance(result, EnvSpec)
        self.assertEqual(result.id, "test-env")


class LoadEnvSpecBadTypeTests(unittest.TestCase):
    def test_unsupported_type_raises_type_error(self) -> None:
        with self.assertRaises(TypeError):
            _load_envspec(42)  # type: ignore[arg-type]

    def test_list_raises_type_error(self) -> None:
        with self.assertRaises(TypeError):
            _load_envspec([])  # type: ignore[arg-type]


# ---------------------------------------------------------------------------
# _load_taskspec
# ---------------------------------------------------------------------------

class LoadTaskSpecTests(unittest.TestCase):
    def test_none_returns_none(self) -> None:
        self.assertIsNone(_load_taskspec(None))

    def test_taskspec_instance_returned_directly(self) -> None:
        spec = _make_task_spec()
        result = _load_taskspec(spec)
        self.assertIs(result, spec)

    def test_dict_loads(self) -> None:
        result = _load_taskspec(_MINIMAL_TASK_DICT)
        self.assertIsInstance(result, TaskSpec)
        self.assertEqual(result.id, "test-task")

    def test_json_file_loads(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "task.json"
            p.write_text(json.dumps(_MINIMAL_TASK_DICT), encoding="utf-8")
            result = _load_taskspec(str(p))
        self.assertIsInstance(result, TaskSpec)
        self.assertEqual(result.id, "test-task")

    def test_yaml_file_loads(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "task.yaml"
            p.write_text("id: test-task\nenv_id: test-env\n", encoding="utf-8")
            result = _load_taskspec(p)
        self.assertIsInstance(result, TaskSpec)
        self.assertEqual(result.id, "test-task")

    def test_unsupported_type_raises_type_error(self) -> None:
        with self.assertRaises(TypeError):
            _load_taskspec(123)  # type: ignore[arg-type]


# ---------------------------------------------------------------------------
# make()
# ---------------------------------------------------------------------------

class MakeTests(unittest.TestCase):
    """Tests for the public make() factory — GymAnythingEnv constructor is patched."""

    def _patch_env(self):
        return mock.patch("gym_anything.config.loading.GymAnythingEnv")

    def test_make_from_dict_returns_env(self) -> None:
        with self._patch_env() as MockEnv:
            MockEnv.return_value = mock.sentinel.env
            result = make(_MINIMAL_ENV_DICT)
        self.assertIs(result, mock.sentinel.env)

    def test_make_validates_env_spec(self) -> None:
        with self._patch_env():
            with mock.patch(
                "gym_anything.config.loading.validate_env_spec"
            ) as mock_validate:
                make(_MINIMAL_ENV_DICT)
        mock_validate.assert_called_once()

    def test_make_with_task_validates_task_spec(self) -> None:
        with self._patch_env():
            with mock.patch(
                "gym_anything.config.loading.validate_task_spec"
            ) as mock_validate:
                make(_MINIMAL_ENV_DICT, task=_MINIMAL_TASK_DICT)
        mock_validate.assert_called_once()

    def test_make_without_task_skips_task_validation(self) -> None:
        with self._patch_env():
            with mock.patch(
                "gym_anything.config.loading.validate_task_spec"
            ) as mock_validate:
                make(_MINIMAL_ENV_DICT)
        mock_validate.assert_not_called()

    def test_make_with_overrides_merges(self) -> None:
        with self._patch_env() as MockEnv:
            MockEnv.return_value = mock.sentinel.env
            result = make(_MINIMAL_ENV_DICT, overrides={"net": True})
        self.assertIs(result, mock.sentinel.env)

    def test_make_from_envspec_instance(self) -> None:
        spec = _make_env_spec()
        with self._patch_env() as MockEnv:
            MockEnv.return_value = mock.sentinel.env
            result = make(spec)
        self.assertIs(result, mock.sentinel.env)


# ---------------------------------------------------------------------------
# from_config()
# ---------------------------------------------------------------------------

class FromConfigTests(unittest.TestCase):
    """Tests for from_config() directory loader."""

    def _write_env(self, env_dir: Path, filename: str = "env.json") -> None:
        (env_dir / filename).write_text(json.dumps(_MINIMAL_ENV_DICT), encoding="utf-8")

    def _write_task(self, task_dir: Path, filename: str = "task.json") -> None:
        task_dir.mkdir(parents=True, exist_ok=True)
        (task_dir / filename).write_text(json.dumps(_MINIMAL_TASK_DICT), encoding="utf-8")

    def test_raises_when_no_env_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(FileNotFoundError):
                with mock.patch("gym_anything.config.loading.GymAnythingEnv"):
                    from_config(tmp)

    def test_raises_when_task_id_not_found(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_dir = Path(tmp)
            self._write_env(env_dir)
            with self.assertRaises(FileNotFoundError):
                with mock.patch("gym_anything.config.loading.GymAnythingEnv"):
                    from_config(tmp, task_id="nonexistent")

    def test_loads_env_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_dir = Path(tmp)
            self._write_env(env_dir)
            with mock.patch("gym_anything.config.loading.GymAnythingEnv") as MockEnv:
                instance = mock.MagicMock()
                MockEnv.return_value = instance
                result = from_config(tmp)
        self.assertIs(result, instance)

    def test_loads_with_explicit_task_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_dir = Path(tmp)
            self._write_env(env_dir)
            task_dir = env_dir / "tasks" / "my-task"
            self._write_task(task_dir)
            with mock.patch("gym_anything.config.loading.GymAnythingEnv") as MockEnv:
                instance = mock.MagicMock()
                MockEnv.return_value = instance
                result = from_config(tmp, task_id="my-task")
        self.assertIs(result, instance)

    def test_auto_selects_single_task(self) -> None:
        """When task_id is omitted and exactly one task folder exists, it is selected."""
        with tempfile.TemporaryDirectory() as tmp:
            env_dir = Path(tmp)
            self._write_env(env_dir)
            task_dir = env_dir / "tasks" / "only-task"
            self._write_task(task_dir)
            with mock.patch("gym_anything.config.loading.GymAnythingEnv") as MockEnv:
                instance = mock.MagicMock()
                MockEnv.return_value = instance
                result = from_config(tmp)
        self.assertIs(result, instance)

    def test_env_yaml_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_dir = Path(tmp)
            self._write_env(env_dir, filename="env.yaml")
            with mock.patch("gym_anything.config.loading.GymAnythingEnv") as MockEnv:
                instance = mock.MagicMock()
                MockEnv.return_value = instance
                result = from_config(tmp)
        self.assertIs(result, instance)

    def test_env_yml_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_dir = Path(tmp)
            self._write_env(env_dir, filename="env.yml")
            with mock.patch("gym_anything.config.loading.GymAnythingEnv") as MockEnv:
                instance = mock.MagicMock()
                MockEnv.return_value = instance
                result = from_config(tmp)
        self.assertIs(result, instance)


if __name__ == "__main__":
    unittest.main()
