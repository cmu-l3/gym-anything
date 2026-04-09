from __future__ import annotations

import unittest

from gym_anything.specs import EnvSpec, TaskSpec
from gym_anything.config.validators import validate_env_spec, validate_task_spec


def _minimal_env_spec(**overrides) -> EnvSpec:
    base = {
        "id": "test-env",
        "observation": [{"type": "rgb_screen"}],
        "action": [{"type": "mouse"}],
    }
    base.update(overrides)
    return EnvSpec.from_dict(base)


def _minimal_task_spec(**overrides) -> TaskSpec:
    base = {
        "id": "test-task",
        "success": {"mode": "program", "spec": {"program": "verifier.py::verify"}},
    }
    base.update(overrides)
    return TaskSpec.from_dict(base)


class ValidateEnvSpecTests(unittest.TestCase):
    # -------------------------------------------------------- valid specs pass
    def test_minimal_spec_passes(self) -> None:
        spec = _minimal_env_spec()
        # Should not raise
        validate_env_spec(spec)

    def test_spec_with_supported_runner_passes(self) -> None:
        for runner in ("docker", "qemu", "qemu_native", "avd", "avd_native", "avf", "local", "apptainer"):
            with self.subTest(runner=runner):
                spec = _minimal_env_spec(runner=runner)
                validate_env_spec(spec)  # must not raise

    def test_spec_with_image_passes(self) -> None:
        spec = _minimal_env_spec(image="ubuntu:22.04")
        validate_env_spec(spec)

    def test_spec_with_multiple_observations_passes(self) -> None:
        spec = _minimal_env_spec(
            observation=[{"type": "rgb_screen"}, {"type": "accessibility_tree"}]
        )
        validate_env_spec(spec)

    def test_spec_with_multiple_actions_passes(self) -> None:
        spec = _minimal_env_spec(
            action=[{"type": "mouse"}, {"type": "keyboard"}]
        )
        validate_env_spec(spec)

    # -------------------------------------------- missing required fields fail
    def test_empty_id_raises_value_error(self) -> None:
        spec = _minimal_env_spec()
        # Manually patch id to empty string (frozen dataclass, use object.__setattr__)
        import dataclasses
        spec_with_empty_id = dataclasses.replace(spec, id="")
        with self.assertRaises(ValueError, msg="Empty id should raise ValueError"):
            validate_env_spec(spec_with_empty_id)

    def test_empty_observation_raises_value_error(self) -> None:
        spec = _minimal_env_spec()
        import dataclasses
        spec_no_obs = dataclasses.replace(spec, observation=[])
        with self.assertRaises(ValueError):
            validate_env_spec(spec_no_obs)

    def test_empty_action_raises_value_error(self) -> None:
        spec = _minimal_env_spec()
        import dataclasses
        spec_no_act = dataclasses.replace(spec, action=[])
        with self.assertRaises(ValueError):
            validate_env_spec(spec_no_act)

    # ---------------------------------------------- unsupported runner fails
    def test_unsupported_runner_raises_value_error(self) -> None:
        spec = _minimal_env_spec(runner="nonexistent_runner")
        with self.assertRaises(ValueError) as ctx:
            validate_env_spec(spec)
        self.assertIn("nonexistent_runner", str(ctx.exception))

    def test_unsupported_runner_error_lists_supported(self) -> None:
        spec = _minimal_env_spec(runner="bad")
        with self.assertRaises(ValueError) as ctx:
            validate_env_spec(spec)
        # Error message should mention at least one known runner
        self.assertIn("docker", str(ctx.exception))

    def test_runner_none_does_not_raise(self) -> None:
        # runner=None means no runner specified → should not fail runner check
        spec = _minimal_env_spec()
        # By default from_dict does not set runner unless specified
        self.assertIsNone(spec.runner)
        validate_env_spec(spec)  # must not raise


class ValidateTaskSpecTests(unittest.TestCase):
    # -------------------------------------------------------- valid specs pass
    def test_minimal_spec_passes(self) -> None:
        spec = _minimal_task_spec()
        validate_task_spec(spec)

    def test_supported_success_modes_pass(self) -> None:
        for mode in ("program", "image_match", "multi"):
            with self.subTest(mode=mode):
                spec = _minimal_task_spec(success={"mode": mode, "spec": {}})
                validate_task_spec(spec)  # must not raise

    def test_spec_with_description_passes(self) -> None:
        spec = _minimal_task_spec(description="Do something useful")
        validate_task_spec(spec)

    def test_spec_with_all_metadata_passes(self) -> None:
        spec = _minimal_task_spec(
            version="2.0",
            description="A complex task",
            name="Complex Task",
            difficulty="hard",
            tags=["benchmark", "complex"],
        )
        validate_task_spec(spec)

    # -------------------------------------------- missing required fields fail
    def test_empty_id_raises_value_error(self) -> None:
        spec = _minimal_task_spec()
        import dataclasses
        spec_empty_id = dataclasses.replace(spec, id="")
        with self.assertRaises(ValueError):
            validate_task_spec(spec_empty_id)

    # ---------------------------------------- unsupported success mode fails
    def test_unsupported_success_mode_raises_value_error(self) -> None:
        spec = _minimal_task_spec(success={"mode": "magic", "spec": {}})
        with self.assertRaises(ValueError) as ctx:
            validate_task_spec(spec)
        self.assertIn("magic", str(ctx.exception))

    def test_unsupported_success_mode_error_lists_supported(self) -> None:
        spec = _minimal_task_spec(success={"mode": "unknown_mode", "spec": {}})
        with self.assertRaises(ValueError) as ctx:
            validate_task_spec(spec)
        # Error message should mention at least one known mode
        self.assertIn("program", str(ctx.exception))

    def test_error_message_contains_bad_mode(self) -> None:
        spec = _minimal_task_spec(success={"mode": "custom", "spec": {}})
        with self.assertRaises(ValueError) as ctx:
            validate_task_spec(spec)
        self.assertIn("custom", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
