"""Extended unit tests for gym_anything.doctor.

Covers DoctorCheck, DoctorReport, render_doctor_text, get_runner_status,
get_recommended_runner, render_doctor_rich, and _check_binary helpers that
the existing test_doctor.py does not exercise.
"""
from __future__ import annotations

import sys
import unittest
from dataclasses import asdict
from pathlib import Path
from unittest import mock

from gym_anything.doctor import (
    DoctorCheck,
    DoctorReport,
    get_recommended_runner,
    get_runner_status,
    render_doctor_rich,
    render_doctor_text,
    run_doctor,
)


# ---------------------------------------------------------------------------
# DoctorCheck
# ---------------------------------------------------------------------------


class TestDoctorCheck(unittest.TestCase):
    def test_ok_check(self) -> None:
        check = DoctorCheck(name="docker_cli", ok=True, detail="docker -> /usr/bin/docker")
        self.assertTrue(check.ok)
        self.assertEqual(check.name, "docker_cli")

    def test_failed_required_check(self) -> None:
        check = DoctorCheck(name="docker_cli", ok=False, detail="docker not found on PATH", required=True)
        self.assertFalse(check.ok)
        self.assertTrue(check.required)

    def test_optional_check_default_required_true(self) -> None:
        check = DoctorCheck(name="ffmpeg", ok=False, detail="not found")
        # default for required is True
        self.assertTrue(check.required)

    def test_to_dict_roundtrip(self) -> None:
        check = DoctorCheck(name="adb", ok=True, detail="adb -> /usr/bin/adb", required=False)
        d = check.to_dict()
        self.assertEqual(d["name"], "adb")
        self.assertTrue(d["ok"])
        self.assertFalse(d["required"])
        self.assertEqual(d["detail"], "adb -> /usr/bin/adb")

    def test_frozen_check_immutable(self) -> None:
        check = DoctorCheck(name="x", ok=True, detail="")
        with self.assertRaises((AttributeError, TypeError)):
            check.name = "y"  # type: ignore[misc]


# ---------------------------------------------------------------------------
# DoctorReport
# ---------------------------------------------------------------------------


class TestDoctorReport(unittest.TestCase):
    def test_empty_report_is_ok(self) -> None:
        report = DoctorReport(checks=[])
        self.assertTrue(report.ok)

    def test_report_ok_when_all_checks_pass(self) -> None:
        report = DoctorReport(checks=[
            DoctorCheck(name="a", ok=True, detail=""),
            DoctorCheck(name="b", ok=True, detail=""),
        ])
        self.assertTrue(report.ok)

    def test_report_fails_on_required_failure(self) -> None:
        report = DoctorReport(checks=[
            DoctorCheck(name="a", ok=True, detail=""),
            DoctorCheck(name="b", ok=False, detail="missing", required=True),
        ])
        self.assertFalse(report.ok)

    def test_report_ok_when_only_optional_fails(self) -> None:
        report = DoctorReport(checks=[
            DoctorCheck(name="a", ok=True, detail=""),
            DoctorCheck(name="ffmpeg", ok=False, detail="not found", required=False),
        ])
        self.assertTrue(report.ok)

    def test_to_dict_structure(self) -> None:
        report = DoctorReport(checks=[
            DoctorCheck(name="docker_cli", ok=True, detail="docker -> /usr/bin/docker"),
        ])
        d = report.to_dict()
        self.assertIn("ok", d)
        self.assertIn("checks", d)
        self.assertIsInstance(d["checks"], list)
        self.assertEqual(len(d["checks"]), 1)
        self.assertEqual(d["checks"][0]["name"], "docker_cli")


# ---------------------------------------------------------------------------
# render_doctor_text
# ---------------------------------------------------------------------------


class TestRenderDoctorText(unittest.TestCase):
    def test_overall_ok_appears_in_output(self) -> None:
        report = DoctorReport(checks=[DoctorCheck(name="a", ok=True, detail="x")])
        text = render_doctor_text(report)
        self.assertIn("overall=ok", text)

    def test_overall_failed_appears_in_output(self) -> None:
        report = DoctorReport(checks=[DoctorCheck(name="a", ok=False, detail="x", required=True)])
        text = render_doctor_text(report)
        self.assertIn("overall=failed", text)

    def test_each_check_has_a_line(self) -> None:
        checks = [
            DoctorCheck(name="docker_cli", ok=True, detail="found"),
            DoctorCheck(name="docker_daemon", ok=False, detail="not running", required=True),
        ]
        report = DoctorReport(checks=checks)
        text = render_doctor_text(report)
        self.assertIn("docker_cli", text)
        self.assertIn("docker_daemon", text)

    def test_warn_label_for_optional_failure(self) -> None:
        report = DoctorReport(checks=[
            DoctorCheck(name="ffmpeg", ok=False, detail="not found", required=False),
        ])
        text = render_doctor_text(report)
        self.assertIn("warn", text)
        self.assertNotIn("fail", text)

    def test_fail_label_for_required_failure(self) -> None:
        report = DoctorReport(checks=[
            DoctorCheck(name="docker_cli", ok=False, detail="not found", required=True),
        ])
        text = render_doctor_text(report)
        self.assertIn("fail", text)

    def test_ok_label_for_passing_check(self) -> None:
        report = DoctorReport(checks=[
            DoctorCheck(name="docker_cli", ok=True, detail="found"),
        ])
        text = render_doctor_text(report)
        self.assertIn("ok:", text)


# ---------------------------------------------------------------------------
# run_doctor — additional runner coverage
# ---------------------------------------------------------------------------


class TestRunDoctorRunners(unittest.TestCase):
    def test_run_doctor_local_always_ok(self) -> None:
        report = run_doctor(runner="local")
        self.assertTrue(report.ok)
        self.assertEqual(len(report.checks), 1)
        self.assertEqual(report.checks[0].name, "local_runner")

    def test_run_doctor_docker_missing_binary_fails(self) -> None:
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None):
            report = run_doctor(runner="docker")
        self.assertFalse(report.ok)

    def test_run_doctor_with_verification_root(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            # Empty root — no verifier files, so scan passes
            report = run_doctor(runner="local", verification_root=root)
        # local runner always ok, scan ok → overall ok
        self.assertTrue(report.ok)
        check_names = [c.name for c in report.checks]
        self.assertIn("verifier_imports", check_names)

    def test_run_doctor_qemu_native_missing_binary(self) -> None:
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None):
            report = run_doctor(runner="qemu_native")
        self.assertFalse(report.ok)


# ---------------------------------------------------------------------------
# get_runner_status
# ---------------------------------------------------------------------------


class TestGetRunnerStatus(unittest.TestCase):
    def test_returns_dict_with_known_runner_keys(self) -> None:
        # Patch which so no binaries are "found" — avoids external calls
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None), \
                mock.patch("gym_anything.doctor.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=1, stdout="", stderr="")
            status = get_runner_status()
        expected_keys = {"docker", "qemu", "qemu_native", "avf", "avd", "avd_native", "apptainer", "local"}
        self.assertEqual(set(status.keys()), expected_keys)

    def test_local_runner_has_no_deps(self) -> None:
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None):
            status = get_runner_status()
        local_status = status.get("local")
        self.assertIsNotNone(local_status)
        # local runner has no external deps
        self.assertEqual(local_status["deps"], {})

    def test_available_key_present_for_all_runners(self) -> None:
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None), \
                mock.patch("gym_anything.doctor.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=1, stdout="", stderr="")
            status = get_runner_status()
        for runner_key, runner_status in status.items():
            self.assertIn("available", runner_status, f"runner {runner_key} missing 'available' key")

    def test_docker_unavailable_when_binary_missing(self) -> None:
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None):
            status = get_runner_status()
        docker_status = status.get("docker")
        self.assertIsNotNone(docker_status)
        self.assertFalse(docker_status["available"])


# ---------------------------------------------------------------------------
# get_recommended_runner
# ---------------------------------------------------------------------------


class TestGetRecommendedRunner(unittest.TestCase):
    def _no_binary_status(self) -> dict:
        """Build a runner-status dict where nothing is available."""
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None), \
                mock.patch("gym_anything.doctor.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=1, stdout="", stderr="")
            return get_runner_status()

    def test_returns_none_or_string(self) -> None:
        status = self._no_binary_status()
        result = get_recommended_runner(runner_status=status)
        self.assertIn(result, (None, "docker", "avf", "qemu", "qemu_native", "avd", "avd_native", "apptainer", "local"))

    def test_linux_prefers_qemu_when_available(self) -> None:
        # Simulate Linux with qemu available
        status = {
            "qemu": {"available": True, "deps": {}},
            "docker": {"available": False, "deps": {}},
            "avf": {"available": False, "reason": "macOS only", "deps": {}},
            "qemu_native": {"available": False, "deps": {}},
            "avd": {"available": False, "deps": {}},
            "avd_native": {"available": False, "deps": {}},
            "apptainer": {"available": False, "deps": {}},
            "local": {"available": True, "deps": {}},
        }
        with mock.patch("gym_anything.doctor._IS_MACOS", False), \
                mock.patch("gym_anything.doctor._IS_LINUX", True):
            result = get_recommended_runner(runner_status=status)
        self.assertEqual(result, "qemu")

    def test_linux_falls_back_to_docker_when_qemu_unavailable(self) -> None:
        status = {
            "qemu": {"available": False, "deps": {}},
            "docker": {"available": True, "deps": {}},
            "avf": {"available": False, "reason": "macOS only", "deps": {}},
            "qemu_native": {"available": False, "deps": {}},
            "avd": {"available": False, "deps": {}},
            "avd_native": {"available": False, "deps": {}},
            "apptainer": {"available": False, "deps": {}},
            "local": {"available": True, "deps": {}},
        }
        with mock.patch("gym_anything.doctor._IS_MACOS", False), \
                mock.patch("gym_anything.doctor._IS_LINUX", True):
            result = get_recommended_runner(runner_status=status)
        self.assertEqual(result, "docker")

    def test_macos_arm_prefers_avf(self) -> None:
        status = {
            "avf": {"available": True, "deps": {}},
            "qemu_native": {"available": True, "deps": {}},
            "docker": {"available": True, "deps": {}},
            "qemu": {"available": False, "reason": "requires Apptainer (Linux only)", "deps": {}},
            "avd": {"available": False, "deps": {}},
            "avd_native": {"available": False, "deps": {}},
            "apptainer": {"available": False, "reason": "Linux only", "deps": {}},
            "local": {"available": True, "deps": {}},
        }
        with mock.patch("gym_anything.doctor._IS_MACOS", True), \
                mock.patch("gym_anything.doctor._IS_ARM", True), \
                mock.patch("gym_anything.doctor._IS_LINUX", False):
            result = get_recommended_runner(runner_status=status)
        self.assertEqual(result, "avf")

    def test_accepts_precomputed_status_dict(self) -> None:
        status = {
            "docker": {"available": True, "deps": {}},
            "qemu": {"available": False, "deps": {}},
            "qemu_native": {"available": False, "deps": {}},
            "avf": {"available": False, "reason": "macOS only", "deps": {}},
            "avd": {"available": False, "deps": {}},
            "avd_native": {"available": False, "deps": {}},
            "apptainer": {"available": False, "deps": {}},
            "local": {"available": True, "deps": {}},
        }
        # Should not call get_runner_status() again when pre-computed dict is provided
        with mock.patch("gym_anything.doctor.get_runner_status") as mock_grs, \
                mock.patch("gym_anything.doctor._IS_MACOS", False), \
                mock.patch("gym_anything.doctor._IS_LINUX", True):
            get_recommended_runner(runner_status=status)
            mock_grs.assert_not_called()


# ---------------------------------------------------------------------------
# render_doctor_rich
# ---------------------------------------------------------------------------


class TestRenderDoctorRich(unittest.TestCase):
    def _make_report(self) -> "DoctorReport":
        return DoctorReport(checks=[
            DoctorCheck(name="local_runner", ok=True, detail="LocalRunner has no prerequisites"),
        ])

    def test_output_is_string(self) -> None:
        report = self._make_report()
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None), \
                mock.patch("gym_anything.doctor.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=1, stdout="", stderr="")
            result = render_doctor_rich(report)
        self.assertIsInstance(result, str)

    def test_output_contains_platform(self) -> None:
        report = self._make_report()
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None), \
                mock.patch("gym_anything.doctor.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=1, stdout="", stderr="")
            result = render_doctor_rich(report)
        self.assertIn("Platform:", result)

    def test_output_contains_runners_section(self) -> None:
        report = self._make_report()
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None), \
                mock.patch("gym_anything.doctor.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=1, stdout="", stderr="")
            result = render_doctor_rich(report)
        self.assertIn("Runners:", result)

    def test_output_lists_runner_keys(self) -> None:
        report = self._make_report()
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None), \
                mock.patch("gym_anything.doctor.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=1, stdout="", stderr="")
            result = render_doctor_rich(report)
        self.assertIn("docker", result)


if __name__ == "__main__":
    unittest.main()
