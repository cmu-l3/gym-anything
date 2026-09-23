from __future__ import annotations

import unittest
from unittest import mock

from gym_anything import get_runner_compatibility
from gym_anything.env import GymAnythingEnv
from gym_anything.specs import EnvSpec


class CompatibilityContractTests(unittest.TestCase):
    def test_docker_user_accounts_are_provisioned(self) -> None:
        compatibility = get_runner_compatibility("docker")
        self.assertEqual(compatibility.user_accounts_mode, "provision_from_spec")
        self.assertTrue(compatibility.live_recording)

    def test_qemu_user_accounts_are_preprovisioned(self) -> None:
        compatibility = get_runner_compatibility("qemu")
        self.assertEqual(compatibility.user_accounts_mode, "preprovisioned_accounts")
        self.assertTrue(compatibility.savevm)

    def test_modal_native_has_disk_checkpoints_without_savevm(self) -> None:
        compatibility = get_runner_compatibility("modal_native")
        self.assertEqual(compatibility.user_accounts_mode, "preprovisioned_accounts")
        self.assertTrue(compatibility.checkpoint_caching)
        self.assertFalse(compatibility.savevm)

    def test_avd_user_accounts_are_metadata_only(self) -> None:
        compatibility = get_runner_compatibility("avd")
        self.assertEqual(compatibility.user_accounts_mode, "metadata_only")
        self.assertTrue(compatibility.checkpoint_caching)

    def test_local_has_no_user_accounts_or_recording(self) -> None:
        compatibility = get_runner_compatibility("local")
        self.assertEqual(compatibility.user_accounts_mode, "unsupported")
        self.assertFalse(compatibility.live_recording)
        self.assertFalse(compatibility.screenshot_video_assembly)

    def test_env_exposes_runtime_compatibility_profile(self) -> None:
        env = GymAnythingEnv(
            EnvSpec.from_dict(
                {
                    "id": "demo-local",
                    "runner": "local",
                    "observation": [{"type": "rgb_screen"}],
                    "action": [{"type": "mouse"}],
                }
            ),
            None,
        )
        profile = env.get_compatibility_profile()
        self.assertEqual(profile["runner"], "local")
        self.assertEqual(profile["user_accounts_mode"], "unsupported")


class QemuWithoutBackendsTests(unittest.TestCase):
    """A Linux host with neither Apptainer nor native QEMU, like the CI runners."""

    def setUp(self) -> None:
        from gym_anything.runtime.runners import registry

        for patcher in (
            mock.patch.object(registry.sys, "platform", "linux"),
            mock.patch.object(registry, "apptainer_available", return_value=False),
            mock.patch.object(registry, "qemu_native_available", return_value=False),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_fact_queries_name_a_class(self) -> None:
        from gym_anything.runtime.runners import registry
        from gym_anything.runtime.runners.qemu_native import QemuNativeRunner

        self.assertIs(registry.resolve_runner_class("qemu"), QemuNativeRunner)
        self.assertEqual(
            get_runner_compatibility("qemu").user_accounts_mode, "preprovisioned_accounts"
        )

    def test_dispatch_fails_with_the_reason(self) -> None:
        from gym_anything.runtime.runners import registry

        spec = EnvSpec.from_dict({"id": "qemu-host-check@1", "runner": "qemu"})
        with self.assertRaisesRegex(RuntimeError, "neither Apptainer nor native QEMU"):
            registry.resolve_runner_class("qemu", spec)


if __name__ == "__main__":
    unittest.main()
