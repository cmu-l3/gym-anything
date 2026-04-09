"""Unit tests for gym_anything.presets helper functions.

Covers:
- Preset catalogue constants (ALL_PRESETS, LINUX_PRESETS, etc.)
- load_preset_env_dict (happy path + unknown name raises ValueError)
- is_windows_preset / is_windows_env
- is_android_preset / is_android_env
- is_avd_preset / is_avd_env
- is_apptainer_preset / is_apptainer_env
- get_os_type
- get_runner_type
- list_presets
"""
from __future__ import annotations

import unittest

from gym_anything.presets import (
    ALL_PRESETS,
    ANDROID_AVD_PRESETS,
    ANDROID_BLISSOS_PRESETS,
    ANDROID_PRESETS,
    APPTAINER_PRESETS,
    LINUX_PRESETS,
    WINDOWS_PRESETS,
    get_os_type,
    get_runner_type,
    is_android_env,
    is_android_preset,
    is_apptainer_env,
    is_apptainer_preset,
    is_avd_env,
    is_avd_preset,
    is_windows_env,
    is_windows_preset,
    list_presets,
    load_preset_env_dict,
)


class PresetCatalogueTests(unittest.TestCase):
    """Tests for the preset catalogue constants."""

    def test_all_presets_is_superset_of_categories(self) -> None:
        for name in LINUX_PRESETS:
            self.assertIn(name, ALL_PRESETS)
        for name in WINDOWS_PRESETS:
            self.assertIn(name, ALL_PRESETS)
        for name in ANDROID_PRESETS:
            self.assertIn(name, ALL_PRESETS)

    def test_android_presets_combines_blissos_and_avd(self) -> None:
        self.assertEqual(set(ANDROID_PRESETS), set(ANDROID_BLISSOS_PRESETS) | set(ANDROID_AVD_PRESETS))

    def test_apptainer_presets_subset_of_linux(self) -> None:
        for name in APPTAINER_PRESETS:
            self.assertIn(name, LINUX_PRESETS)

    def test_no_duplicate_names_in_all_presets(self) -> None:
        self.assertEqual(len(ALL_PRESETS), len(set(ALL_PRESETS)))

    def test_known_names_present(self) -> None:
        self.assertIn("x11-lite", ALL_PRESETS)
        self.assertIn("ubuntu-gnome", ALL_PRESETS)
        self.assertIn("windows-11", ALL_PRESETS)
        self.assertIn("android-14", ALL_PRESETS)
        self.assertIn("android-avd-35", ALL_PRESETS)
        self.assertIn("android-avd-34", ALL_PRESETS)
        self.assertIn("apptainer-xfce-gpu", ALL_PRESETS)


class LoadPresetEnvDictTests(unittest.TestCase):
    """Tests for load_preset_env_dict."""

    def test_load_ubuntu_gnome_returns_dict(self) -> None:
        data = load_preset_env_dict("ubuntu-gnome")
        self.assertIsInstance(data, dict)

    def test_load_ubuntu_gnome_has_id(self) -> None:
        data = load_preset_env_dict("ubuntu-gnome")
        self.assertIn("id", data)

    def test_load_x11_lite_has_observation(self) -> None:
        data = load_preset_env_dict("x11-lite")
        self.assertIn("observation", data)

    def test_load_windows_11_has_os_type_windows(self) -> None:
        data = load_preset_env_dict("windows-11")
        self.assertEqual(data.get("os_type"), "windows")

    def test_load_android_14_has_os_type_android(self) -> None:
        data = load_preset_env_dict("android-14")
        self.assertEqual(data.get("os_type"), "android")

    def test_load_apptainer_has_runner_apptainer(self) -> None:
        data = load_preset_env_dict("apptainer-xfce-gpu")
        self.assertEqual(data.get("runner"), "apptainer")

    def test_load_android_avd_35_has_runner_avd(self) -> None:
        data = load_preset_env_dict("android-avd-35")
        self.assertEqual(data.get("runner"), "avd")

    def test_load_all_presets_without_error(self) -> None:
        for name in ALL_PRESETS:
            with self.subTest(preset=name):
                data = load_preset_env_dict(name)
                self.assertIsInstance(data, dict)

    def test_unknown_preset_raises_value_error(self) -> None:
        with self.assertRaises(ValueError):
            load_preset_env_dict("nonexistent-preset")

    def test_unknown_preset_error_message_lists_available(self) -> None:
        with self.assertRaises(ValueError) as ctx:
            load_preset_env_dict("bad-name")
        self.assertIn("bad-name", str(ctx.exception))


class IsWindowsTests(unittest.TestCase):
    """Tests for is_windows_preset and is_windows_env."""

    def test_windows_preset_name(self) -> None:
        self.assertTrue(is_windows_preset("windows-11"))

    def test_linux_preset_not_windows(self) -> None:
        self.assertFalse(is_windows_preset("ubuntu-gnome"))

    def test_android_preset_not_windows(self) -> None:
        self.assertFalse(is_windows_preset("android-14"))

    def test_is_windows_env_explicit_os_type(self) -> None:
        self.assertTrue(is_windows_env({"os_type": "windows"}))

    def test_is_windows_env_base_preset(self) -> None:
        self.assertTrue(is_windows_env({"base": "windows-11"}))

    def test_is_windows_env_linux_os_type(self) -> None:
        self.assertFalse(is_windows_env({"os_type": "linux"}))

    def test_is_windows_env_empty_dict(self) -> None:
        self.assertFalse(is_windows_env({}))

    def test_is_windows_env_android_base(self) -> None:
        self.assertFalse(is_windows_env({"base": "android-14"}))


class IsAndroidTests(unittest.TestCase):
    """Tests for is_android_preset and is_android_env."""

    def test_android_blissos_preset(self) -> None:
        self.assertTrue(is_android_preset("android-14"))

    def test_android_avd_preset(self) -> None:
        self.assertTrue(is_android_preset("android-avd-35"))
        self.assertTrue(is_android_preset("android-avd-34"))

    def test_linux_preset_not_android(self) -> None:
        self.assertFalse(is_android_preset("ubuntu-gnome"))

    def test_is_android_env_explicit_os_type(self) -> None:
        self.assertTrue(is_android_env({"os_type": "android"}))

    def test_is_android_env_base_preset(self) -> None:
        self.assertTrue(is_android_env({"base": "android-14"}))

    def test_is_android_env_avd_base(self) -> None:
        self.assertTrue(is_android_env({"base": "android-avd-35"}))

    def test_is_android_env_windows_os_type(self) -> None:
        self.assertFalse(is_android_env({"os_type": "windows"}))

    def test_is_android_env_empty_dict(self) -> None:
        self.assertFalse(is_android_env({}))


class IsAvdTests(unittest.TestCase):
    """Tests for is_avd_preset and is_avd_env."""

    def test_avd_preset_names(self) -> None:
        self.assertTrue(is_avd_preset("android-avd-35"))
        self.assertTrue(is_avd_preset("android-avd-34"))

    def test_blissos_preset_not_avd(self) -> None:
        self.assertFalse(is_avd_preset("android-14"))

    def test_linux_preset_not_avd(self) -> None:
        self.assertFalse(is_avd_preset("ubuntu-gnome"))

    def test_is_avd_env_runner_field(self) -> None:
        self.assertTrue(is_avd_env({"runner": "avd"}))

    def test_is_avd_env_base_preset(self) -> None:
        self.assertTrue(is_avd_env({"base": "android-avd-35"}))

    def test_is_avd_env_docker_runner(self) -> None:
        self.assertFalse(is_avd_env({"runner": "docker"}))

    def test_is_avd_env_empty_dict(self) -> None:
        self.assertFalse(is_avd_env({}))


class IsApptainerTests(unittest.TestCase):
    """Tests for is_apptainer_preset and is_apptainer_env."""

    def test_apptainer_preset_name(self) -> None:
        self.assertTrue(is_apptainer_preset("apptainer-xfce-gpu"))

    def test_linux_non_apptainer_preset(self) -> None:
        self.assertFalse(is_apptainer_preset("ubuntu-gnome"))

    def test_is_apptainer_env_runner_field(self) -> None:
        self.assertTrue(is_apptainer_env({"runner": "apptainer"}))

    def test_is_apptainer_env_base_preset(self) -> None:
        self.assertTrue(is_apptainer_env({"base": "apptainer-xfce-gpu"}))

    def test_is_apptainer_env_docker_runner(self) -> None:
        self.assertFalse(is_apptainer_env({"runner": "docker"}))

    def test_is_apptainer_env_empty_dict(self) -> None:
        self.assertFalse(is_apptainer_env({}))


class GetOsTypeTests(unittest.TestCase):
    """Tests for get_os_type."""

    def test_explicit_linux(self) -> None:
        self.assertEqual(get_os_type({"os_type": "linux"}), "linux")

    def test_explicit_windows(self) -> None:
        self.assertEqual(get_os_type({"os_type": "windows"}), "windows")

    def test_explicit_android(self) -> None:
        self.assertEqual(get_os_type({"os_type": "android"}), "android")

    def test_defaults_to_linux(self) -> None:
        self.assertEqual(get_os_type({}), "linux")

    def test_loaded_ubuntu_gnome_preset(self) -> None:
        data = load_preset_env_dict("ubuntu-gnome")
        # ubuntu-gnome doesn't set os_type explicitly — defaults to "linux"
        self.assertEqual(get_os_type(data), "linux")

    def test_loaded_windows_preset(self) -> None:
        data = load_preset_env_dict("windows-11")
        self.assertEqual(get_os_type(data), "windows")


class GetRunnerTypeTests(unittest.TestCase):
    """Tests for get_runner_type."""

    def test_explicit_docker(self) -> None:
        self.assertEqual(get_runner_type({"runner": "docker"}), "docker")

    def test_explicit_qemu(self) -> None:
        self.assertEqual(get_runner_type({"runner": "qemu"}), "qemu")

    def test_explicit_avd(self) -> None:
        self.assertEqual(get_runner_type({"runner": "avd"}), "avd")

    def test_explicit_apptainer(self) -> None:
        self.assertEqual(get_runner_type({"runner": "apptainer"}), "apptainer")

    def test_explicit_local(self) -> None:
        self.assertEqual(get_runner_type({"runner": "local"}), "local")

    def test_apptainer_inferred_from_base(self) -> None:
        self.assertEqual(get_runner_type({"base": "apptainer-xfce-gpu"}), "apptainer")

    def test_avd_inferred_from_base(self) -> None:
        self.assertEqual(get_runner_type({"base": "android-avd-35"}), "avd")

    def test_android_blissos_inferred_as_qemu(self) -> None:
        self.assertEqual(get_runner_type({"os_type": "android", "base": "android-14"}), "qemu")

    def test_windows_inferred_as_qemu(self) -> None:
        self.assertEqual(get_runner_type({"os_type": "windows"}), "qemu")

    def test_fallback_returns_qemu(self) -> None:
        # Empty dict has no runner field and is not apptainer/avd/android/windows
        self.assertEqual(get_runner_type({}), "qemu")


class ListPresetsTests(unittest.TestCase):
    """Tests for list_presets."""

    def test_returns_dict(self) -> None:
        result = list_presets()
        self.assertIsInstance(result, dict)

    def test_has_expected_keys(self) -> None:
        result = list_presets()
        for key in ("linux", "windows", "android", "android_avd", "android_blissos", "apptainer"):
            self.assertIn(key, result, msg=f"Missing key: {key}")

    def test_linux_key_contains_x11_lite(self) -> None:
        result = list_presets()
        self.assertIn("x11-lite", result["linux"])

    def test_windows_key_contains_windows_11(self) -> None:
        result = list_presets()
        self.assertIn("windows-11", result["windows"])

    def test_android_key_contains_all_android(self) -> None:
        result = list_presets()
        for name in ANDROID_PRESETS:
            self.assertIn(name, result["android"])

    def test_apptainer_key_matches_constant(self) -> None:
        result = list_presets()
        self.assertEqual(set(result["apptainer"]), set(APPTAINER_PRESETS))


if __name__ == "__main__":
    unittest.main()
