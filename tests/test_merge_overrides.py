from __future__ import annotations

import unittest

from gym_anything.specs import (
    ApptainerSpec,
    EnvSpec,
    RecordingSpec,
    RuntimeResources,
    SecuritySpec,
)


def _base_env(**kwargs: object) -> EnvSpec:
    """Return a minimal valid EnvSpec for use as the base in merge tests."""
    defaults: dict = {
        "id": "test-env",
        "runner": "docker",
        "observation": [{"type": "rgb_screen"}],
        "action": [{"type": "mouse"}],
    }
    defaults.update(kwargs)
    return EnvSpec.from_dict(defaults)


class TestMergeOverridesScalarFields(unittest.TestCase):
    """merge_overrides with plain scalar values replaces the field directly."""

    def test_override_description(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"description": "New description"})
        self.assertEqual(result.description, "New description")

    def test_override_runner(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"runner": "qemu"})
        self.assertEqual(result.runner, "qemu")

    def test_override_image(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"image": "ubuntu:22.04"})
        self.assertEqual(result.image, "ubuntu:22.04")

    def test_override_version(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"version": "2.0"})
        self.assertEqual(result.version, "2.0")

    def test_override_does_not_change_id(self) -> None:
        """The id should remain unchanged even if omitted from overrides dict."""
        env = _base_env()
        result = env.merge_overrides({"description": "changed"})
        self.assertEqual(result.id, "test-env")

    def test_empty_overrides_returns_equivalent_env(self) -> None:
        env = _base_env()
        result = env.merge_overrides({})
        self.assertEqual(result.id, env.id)
        self.assertEqual(result.runner, env.runner)

    def test_multiple_scalar_overrides(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"description": "desc", "runner": "local"})
        self.assertEqual(result.description, "desc")
        self.assertEqual(result.runner, "local")

    def test_override_returns_new_env_spec(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"description": "new"})
        self.assertIsInstance(result, EnvSpec)
        self.assertIsNot(result, env)


class TestMergeOverridesResources(unittest.TestCase):
    """merge_overrides merges nested RuntimeResources dicts shallowly."""

    def test_override_cpu(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"resources": {"cpu": 4.0}})
        self.assertEqual(result.resources.cpu, 4.0)

    def test_override_mem_gb(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"resources": {"mem_gb": 8}})
        self.assertEqual(result.resources.mem_gb, 8)

    def test_override_gpu(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"resources": {"gpu": 1}})
        self.assertEqual(result.resources.gpu, 1)

    def test_unmentioned_resource_fields_preserved(self) -> None:
        """Overriding cpu should not wipe mem_gb if it was already set."""
        base = EnvSpec.from_dict(
            {
                "id": "r-env",
                "runner": "docker",
                "observation": [{"type": "rgb_screen"}],
                "action": [{"type": "mouse"}],
                "resources": {"cpu": 2.0, "mem_gb": 4},
            }
        )
        result = base.merge_overrides({"resources": {"cpu": 8.0}})
        self.assertEqual(result.resources.cpu, 8.0)
        self.assertEqual(result.resources.mem_gb, 4)

    def test_resources_result_is_runtime_resources(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"resources": {"cpu": 2.0}})
        self.assertIsInstance(result.resources, RuntimeResources)


class TestMergeOverridesSecurity(unittest.TestCase):
    """merge_overrides merges nested SecuritySpec dicts shallowly."""

    def test_override_user(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"security": {"user": "0:0"}})
        self.assertEqual(result.security.user, "0:0")

    def test_override_privileged(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"security": {"privileged": True}})
        self.assertTrue(result.security.privileged)

    def test_security_result_is_security_spec(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"security": {"user": "500:500"}})
        self.assertIsInstance(result.security, SecuritySpec)

    def test_unmentioned_security_fields_preserved(self) -> None:
        base = EnvSpec.from_dict(
            {
                "id": "s-env",
                "runner": "docker",
                "observation": [{"type": "rgb_screen"}],
                "action": [{"type": "mouse"}],
                "security": {"user": "1000:1000", "privileged": False},
            }
        )
        result = base.merge_overrides({"security": {"user": "0:0"}})
        self.assertEqual(result.security.user, "0:0")
        self.assertFalse(result.security.privileged)


class TestMergeOverridesRecording(unittest.TestCase):
    """merge_overrides merges nested RecordingSpec dicts shallowly."""

    def test_override_video_fps(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"recording": {"video_fps": 30}})
        self.assertEqual(result.recording.video_fps, 30)

    def test_override_output_dir(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"recording": {"output_dir": "/tmp/out"}})
        self.assertEqual(result.recording.output_dir, "/tmp/out")

    def test_recording_result_is_recording_spec(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"recording": {"video_fps": 5}})
        self.assertIsInstance(result.recording, RecordingSpec)

    def test_unmentioned_recording_fields_preserved(self) -> None:
        base = EnvSpec.from_dict(
            {
                "id": "rec-env",
                "runner": "docker",
                "observation": [{"type": "rgb_screen"}],
                "action": [{"type": "mouse"}],
                "recording": {"video_fps": 10, "video_codec": "libx265"},
            }
        )
        result = base.merge_overrides({"recording": {"video_fps": 24}})
        self.assertEqual(result.recording.video_fps, 24)
        self.assertEqual(result.recording.video_codec, "libx265")


class TestMergeOverridesApptainer(unittest.TestCase):
    """merge_overrides handles the apptainer field (nullable nested spec)."""

    def test_set_apptainer_on_env_without_apptainer(self) -> None:
        env = _base_env()
        self.assertIsNone(env.apptainer)
        result = env.merge_overrides({"apptainer": {"sif": "/images/myenv.sif"}})
        self.assertIsNotNone(result.apptainer)
        self.assertEqual(result.apptainer.sif, "/images/myenv.sif")

    def test_set_apptainer_creates_apptainer_spec(self) -> None:
        env = _base_env()
        result = env.merge_overrides({"apptainer": {"image": "docker://ubuntu:22.04"}})
        self.assertIsInstance(result.apptainer, ApptainerSpec)

    def test_override_existing_apptainer_field(self) -> None:
        base = EnvSpec.from_dict(
            {
                "id": "appt-env",
                "runner": "apptainer",
                "observation": [{"type": "rgb_screen"}],
                "action": [{"type": "mouse"}],
                "apptainer": {"sif": "/old/path.sif", "fakeroot": False},
            }
        )
        result = base.merge_overrides({"apptainer": {"sif": "/new/path.sif"}})
        self.assertEqual(result.apptainer.sif, "/new/path.sif")

    def test_existing_apptainer_field_preserved_when_not_mentioned(self) -> None:
        base = EnvSpec.from_dict(
            {
                "id": "appt-env2",
                "runner": "apptainer",
                "observation": [{"type": "rgb_screen"}],
                "action": [{"type": "mouse"}],
                "apptainer": {"sif": "/base.sif", "fakeroot": True},
            }
        )
        result = base.merge_overrides({"apptainer": {"sif": "/new.sif"}})
        # fakeroot was True in the base; after merge only sif is updated
        self.assertTrue(result.apptainer.fakeroot)
        self.assertEqual(result.apptainer.sif, "/new.sif")


class TestMergeOverridesImmutability(unittest.TestCase):
    """merge_overrides must not mutate the original EnvSpec."""

    def test_original_unchanged_after_scalar_override(self) -> None:
        env = _base_env()
        original_runner = env.runner
        env.merge_overrides({"runner": "local"})
        self.assertEqual(env.runner, original_runner)

    def test_original_unchanged_after_resources_override(self) -> None:
        env = _base_env()
        original_cpu = env.resources.cpu
        env.merge_overrides({"resources": {"cpu": 99.0}})
        self.assertEqual(env.resources.cpu, original_cpu)

    def test_original_unchanged_after_security_override(self) -> None:
        env = _base_env()
        original_user = env.security.user
        env.merge_overrides({"security": {"user": "0:0"}})
        self.assertEqual(env.security.user, original_user)


if __name__ == "__main__":
    unittest.main()
