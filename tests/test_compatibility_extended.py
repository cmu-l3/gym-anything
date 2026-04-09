from __future__ import annotations

import unittest

from gym_anything.compatibility import (
    RunnerCompatibility,
    get_runner_compatibility,
    get_runner_compatibility_matrix,
    infer_runner_key_from_name,
    list_supported_runners,
    render_compatibility_text,
)


class TestListSupportedRunners(unittest.TestCase):
    def test_returns_list(self) -> None:
        runners = list_supported_runners()
        self.assertIsInstance(runners, list)

    def test_contains_all_eight_runners(self) -> None:
        runners = list_supported_runners()
        expected = {
            "docker",
            "qemu",
            "qemu_native",
            "avd",
            "avd_native",
            "apptainer",
            "avf",
            "local",
        }
        self.assertEqual(set(runners), expected)

    def test_length_is_eight(self) -> None:
        self.assertEqual(len(list_supported_runners()), 8)


class TestGetRunnerCompatibilityAllRunners(unittest.TestCase):
    """Covers all 8 runners, including the 4 not tested by test_compatibility.py."""

    def _assert_fields(
        self,
        runner: str,
        *,
        display_name: str,
        live_recording: bool,
        screenshot_video_assembly: bool,
        checkpoint_caching: bool,
        savevm: bool,
        user_accounts_mode: str,
    ) -> None:
        compat = get_runner_compatibility(runner)
        self.assertEqual(compat.runner, runner)
        self.assertEqual(compat.display_name, display_name)
        self.assertEqual(compat.live_recording, live_recording)
        self.assertEqual(compat.screenshot_video_assembly, screenshot_video_assembly)
        self.assertEqual(compat.checkpoint_caching, checkpoint_caching)
        self.assertEqual(compat.savevm, savevm)
        self.assertEqual(compat.user_accounts_mode, user_accounts_mode)

    # --- runners already covered by test_compatibility.py (regression guard) ---

    def test_docker(self) -> None:
        self._assert_fields(
            "docker",
            display_name="DockerRunner",
            live_recording=True,
            screenshot_video_assembly=True,
            checkpoint_caching=True,
            savevm=False,
            user_accounts_mode="provision_from_spec",
        )

    def test_qemu(self) -> None:
        self._assert_fields(
            "qemu",
            display_name="QemuApptainerRunner",
            live_recording=False,
            screenshot_video_assembly=True,
            checkpoint_caching=True,
            savevm=True,
            user_accounts_mode="preprovisioned_accounts",
        )

    def test_avd(self) -> None:
        self._assert_fields(
            "avd",
            display_name="AVDApptainerRunner",
            live_recording=False,
            screenshot_video_assembly=True,
            checkpoint_caching=True,
            savevm=False,
            user_accounts_mode="metadata_only",
        )

    def test_local(self) -> None:
        self._assert_fields(
            "local",
            display_name="LocalRunner",
            live_recording=False,
            screenshot_video_assembly=False,
            checkpoint_caching=False,
            savevm=False,
            user_accounts_mode="unsupported",
        )

    # --- runners NOT previously covered ---

    def test_qemu_native(self) -> None:
        self._assert_fields(
            "qemu_native",
            display_name="QemuNativeRunner",
            live_recording=False,
            screenshot_video_assembly=True,
            checkpoint_caching=True,
            savevm=True,
            user_accounts_mode="preprovisioned_accounts",
        )

    def test_avd_native(self) -> None:
        self._assert_fields(
            "avd_native",
            display_name="AVDNativeRunner",
            live_recording=False,
            screenshot_video_assembly=True,
            checkpoint_caching=True,
            savevm=False,
            user_accounts_mode="metadata_only",
        )

    def test_apptainer(self) -> None:
        self._assert_fields(
            "apptainer",
            display_name="ApptainerDirectRunner",
            live_recording=False,
            screenshot_video_assembly=True,
            checkpoint_caching=False,
            savevm=False,
            user_accounts_mode="preprovisioned_accounts",
        )

    def test_avf(self) -> None:
        self._assert_fields(
            "avf",
            display_name="AVFRunner",
            live_recording=False,
            screenshot_video_assembly=True,
            checkpoint_caching=False,
            savevm=False,
            user_accounts_mode="preprovisioned_accounts",
        )

    def test_unknown_runner_raises_key_error(self) -> None:
        with self.assertRaises(KeyError) as ctx:
            get_runner_compatibility("nonexistent_runner")
        self.assertIn("nonexistent_runner", str(ctx.exception))
        self.assertIn("supported runners", str(ctx.exception))

    def test_unknown_runner_error_lists_supported(self) -> None:
        with self.assertRaises(KeyError) as ctx:
            get_runner_compatibility("bogus")
        # Error message should mention at least one known runner
        self.assertIn("docker", str(ctx.exception))


class TestRunnerCompatibilityToDict(unittest.TestCase):
    def test_to_dict_returns_dict(self) -> None:
        compat = get_runner_compatibility("docker")
        result = compat.to_dict()
        self.assertIsInstance(result, dict)

    def test_to_dict_contains_all_fields(self) -> None:
        compat = get_runner_compatibility("docker")
        d = compat.to_dict()
        for field in (
            "runner",
            "display_name",
            "live_recording",
            "screenshot_video_assembly",
            "checkpoint_caching",
            "savevm",
            "user_accounts_mode",
            "notes",
        ):
            self.assertIn(field, d)

    def test_to_dict_values_match(self) -> None:
        compat = get_runner_compatibility("qemu_native")
        d = compat.to_dict()
        self.assertEqual(d["runner"], "qemu_native")
        self.assertEqual(d["user_accounts_mode"], "preprovisioned_accounts")
        self.assertTrue(d["savevm"])
        self.assertFalse(d["live_recording"])

    def test_to_dict_notes_is_list(self) -> None:
        compat = get_runner_compatibility("docker")
        self.assertIsInstance(compat.to_dict()["notes"], list)
        self.assertGreater(len(compat.to_dict()["notes"]), 0)

    def test_local_runner_notes_is_list(self) -> None:
        compat = get_runner_compatibility("local")
        self.assertIsInstance(compat.to_dict()["notes"], list)


class TestGetRunnerCompatibilityMatrix(unittest.TestCase):
    def test_returns_list(self) -> None:
        matrix = get_runner_compatibility_matrix()
        self.assertIsInstance(matrix, list)

    def test_length_equals_supported_runners(self) -> None:
        matrix = get_runner_compatibility_matrix()
        self.assertEqual(len(matrix), len(list_supported_runners()))

    def test_all_entries_are_runner_compatibility(self) -> None:
        for entry in get_runner_compatibility_matrix():
            self.assertIsInstance(entry, RunnerCompatibility)

    def test_matrix_covers_all_runner_keys(self) -> None:
        matrix_runners = {rc.runner for rc in get_runner_compatibility_matrix()}
        self.assertEqual(matrix_runners, set(list_supported_runners()))

    def test_matrix_docker_entry_is_correct(self) -> None:
        matrix = {rc.runner: rc for rc in get_runner_compatibility_matrix()}
        self.assertTrue(matrix["docker"].live_recording)
        self.assertEqual(matrix["docker"].user_accounts_mode, "provision_from_spec")


class TestInferRunnerKeyFromName(unittest.TestCase):
    def _check(self, name: str, expected_key: str) -> None:
        result = infer_runner_key_from_name(name)
        self.assertEqual(result, expected_key)

    def test_docker_runner(self) -> None:
        self._check("DockerRunner", "docker")

    def test_qemu_apptainer_runner(self) -> None:
        self._check("QemuApptainerRunner", "qemu")

    def test_qemu_native_runner(self) -> None:
        self._check("QemuNativeRunner", "qemu_native")

    def test_avd_apptainer_runner(self) -> None:
        self._check("AVDApptainerRunner", "avd")

    def test_avd_native_runner(self) -> None:
        self._check("AVDNativeRunner", "avd_native")

    def test_avf_runner(self) -> None:
        self._check("AVFRunner", "avf")

    def test_apptainer_direct_runner(self) -> None:
        self._check("ApptainerDirectRunner", "apptainer")

    def test_local_runner(self) -> None:
        self._check("LocalRunner", "local")

    def test_case_insensitive_lowercase(self) -> None:
        self._check("dockerrunner", "docker")

    def test_case_insensitive_mixed(self) -> None:
        self._check("LOCALRUNNER", "local")

    def test_unknown_name_returns_none(self) -> None:
        self.assertIsNone(infer_runner_key_from_name("UnknownRunner"))

    def test_empty_string_returns_none(self) -> None:
        self.assertIsNone(infer_runner_key_from_name(""))

    def test_partial_name_returns_none(self) -> None:
        self.assertIsNone(infer_runner_key_from_name("Docker"))


class TestRenderCompatibilityText(unittest.TestCase):
    def test_returns_string(self) -> None:
        result = render_compatibility_text([get_runner_compatibility("docker")])
        self.assertIsInstance(result, str)

    def test_single_runner_contains_runner_key(self) -> None:
        result = render_compatibility_text([get_runner_compatibility("docker")])
        self.assertIn("docker", result)

    def test_single_runner_contains_display_name(self) -> None:
        result = render_compatibility_text([get_runner_compatibility("docker")])
        self.assertIn("DockerRunner", result)

    def test_live_recording_yes_for_docker(self) -> None:
        result = render_compatibility_text([get_runner_compatibility("docker")])
        self.assertIn("live_recording=yes", result)

    def test_live_recording_no_for_local(self) -> None:
        result = render_compatibility_text([get_runner_compatibility("local")])
        self.assertIn("live_recording=no", result)

    def test_savevm_yes_for_qemu(self) -> None:
        result = render_compatibility_text([get_runner_compatibility("qemu")])
        self.assertIn("savevm=yes", result)

    def test_savevm_no_for_docker(self) -> None:
        result = render_compatibility_text([get_runner_compatibility("docker")])
        self.assertIn("savevm=no", result)

    def test_user_accounts_mode_in_output(self) -> None:
        result = render_compatibility_text([get_runner_compatibility("avd")])
        self.assertIn("metadata_only", result)

    def test_notes_are_included(self) -> None:
        result = render_compatibility_text([get_runner_compatibility("docker")])
        # Docker has notes about FFmpeg recording
        self.assertIn("FFmpeg", result)

    def test_multiple_runners_separated_by_newlines(self) -> None:
        compat_list = [
            get_runner_compatibility("docker"),
            get_runner_compatibility("local"),
        ]
        result = render_compatibility_text(compat_list)
        self.assertIn("docker", result)
        self.assertIn("local", result)
        self.assertIn("\n", result)

    def test_empty_iterable_returns_empty_string(self) -> None:
        result = render_compatibility_text([])
        self.assertEqual(result, "")

    def test_full_matrix_renders_all_runners(self) -> None:
        matrix = get_runner_compatibility_matrix()
        result = render_compatibility_text(matrix)
        for runner in list_supported_runners():
            self.assertIn(runner, result)


if __name__ == "__main__":
    unittest.main()
