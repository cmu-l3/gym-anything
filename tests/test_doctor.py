from __future__ import annotations

import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

from gym_anything import doctor
from gym_anything.doctor import (
    DEFAULT_KVM_DEVICE,
    check_kvm_access,
    get_available_runners,
    get_runner_status,
    render_doctor_text,
    run_doctor,
    scan_verifier_imports,
)


class DoctorTests(unittest.TestCase):
    def test_run_doctor_reports_missing_docker_binary(self) -> None:
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None):
            report = run_doctor(runner="docker")

        self.assertFalse(report.ok)
        self.assertTrue(any(check.name == "docker" and not check.ok for check in report.checks))

    def test_run_doctor_accepts_local_runner_without_system_tools(self) -> None:
        report = run_doctor(runner="local")

        self.assertTrue(report.ok)
        self.assertEqual(report.checks[0].name, "local_runner")

    def test_modal_native_doctor_requires_filesystem_capable_sdk(self) -> None:
        old_modal = types.SimpleNamespace(__version__="1.3.9")
        with mock.patch.dict(sys.modules, {"modal": old_modal}):
            report = run_doctor(runner="modal_native")

        self.assertFalse(report.ok)
        self.assertEqual(report.checks[0].name, "modal_native_runner")
        self.assertIn("modal>=1.4", report.checks[0].detail)

    def test_scan_verifier_imports_detects_missing_module(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env_dir = root / "demo_env"
            task_dir = env_dir / "tasks" / "demo"
            task_dir.mkdir(parents=True)
            (task_dir / "verifier.py").write_text(
                "import definitely_missing_dependency\n"
                "def verify(traj, env_info, task_info):\n"
                "    return {'passed': False, 'score': 0}\n",
                encoding="utf-8",
            )

            check = scan_verifier_imports(root)

        self.assertFalse(check.ok)
        self.assertIn("definitely_missing_dependency", check.detail)

    def test_render_doctor_text_includes_overall_status(self) -> None:
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None):
            report = run_doctor(runner="docker")

        rendered = render_doctor_text(report)

        self.assertIn("overall=failed", rendered)


class KvmProbeIntegrationTests(unittest.TestCase):
    """KVM is part of get_runner_status for QEMU-family runners on Linux.

    The family key resolves to a concrete class per host, so these tests pin
    the selector (apptainer present) and mock the probes at the doctor
    module, where the runner classes read them.
    """

    def test_check_kvm_access_raises_with_actionable_message(self) -> None:
        # Pick a path that definitely doesn't exist; we don't want this test
        # to depend on host KVM availability.
        missing = "/definitely/not/a/real/kvm/device"
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            check_kvm_access(missing)

    def test_get_runner_status_marks_qemu_unavailable_when_kvm_missing(self) -> None:
        with mock.patch.object(doctor, "_IS_LINUX", True), \
             mock.patch.object(doctor, "_IS_MACOS", False), \
             mock.patch("gym_anything.runtime.runners.registry.apptainer_available", return_value=True), \
             mock.patch("gym_anything.doctor.shutil.which", return_value="/usr/bin/apptainer"), \
             mock.patch.object(
                doctor, "_probe_kvm_openable", return_value=(False, "/dev/kvm does not exist")
             ):
            status = get_runner_status()

        qemu = status["qemu"]
        self.assertFalse(qemu["available"])
        self.assertIn("kvm", qemu["deps"])
        self.assertFalse(qemu["deps"]["kvm"]["installed"])
        self.assertEqual(qemu["deps"]["kvm"]["reason"], "/dev/kvm does not exist")

    def test_get_runner_status_marks_qemu_available_when_kvm_ok(self) -> None:
        with mock.patch.object(doctor, "_IS_LINUX", True), \
             mock.patch.object(doctor, "_IS_MACOS", False), \
             mock.patch("gym_anything.runtime.runners.registry.apptainer_available", return_value=True), \
             mock.patch("gym_anything.doctor.shutil.which", return_value="/usr/bin/apptainer"), \
             mock.patch.object(doctor, "_probe_kvm_openable", return_value=(True, None)):
            status = get_runner_status()

        qemu = status["qemu"]
        self.assertTrue(qemu["available"])
        self.assertTrue(qemu["deps"]["kvm"]["installed"])
        self.assertEqual(qemu["deps"]["kvm"]["path"], DEFAULT_KVM_DEVICE)

    def test_get_runner_status_skips_kvm_probe_on_macos(self) -> None:
        macos_sys = types.SimpleNamespace(platform="darwin")
        with mock.patch.object(doctor, "_IS_LINUX", False), \
             mock.patch.object(doctor, "_IS_MACOS", True), \
             mock.patch("gym_anything.runtime.runners.registry.sys", macos_sys), \
             mock.patch.object(doctor, "_probe_kvm_openable") as probe:
            status = get_runner_status()
        # On macOS the qemu family resolves to the native-QEMU path — doctor
        # reports the class dispatch would actually use, so there is no
        # platform block and no KVM probe.
        self.assertIsNone(status["qemu"].get("reason"))
        self.assertNotIn("kvm", status["qemu"]["deps"])
        probe.assert_not_called()

    def test_get_available_runners_returns_only_ready(self) -> None:
        fake_status = {
            "docker": {"available": True, "deps": {}},
            "qemu": {"available": False, "deps": {}},
            "local": {"available": True, "deps": {}},
        }
        self.assertEqual(
            sorted(get_available_runners(fake_status)),
            ["docker", "local"],
        )


if __name__ == "__main__":
    unittest.main()


class CwdShadowingTests(unittest.TestCase):
    """The cwd-beats-installed-packages incident class, mechanized."""

    def test_clean_checkout_does_not_warn(self) -> None:
        from gym_anything.doctor import check_cwd_shadowing

        check = check_cwd_shadowing()
        self.assertTrue(check.ok, msg=check.detail)

    def test_mismatched_pillar_root_warns(self) -> None:
        import types as _types

        from gym_anything import doctor as _doctor

        with tempfile.TemporaryDirectory() as tmp:
            cwd = Path(tmp).resolve()
            (cwd / "agents").mkdir()
            (cwd / "agents" / "__init__.py").write_text("")
            fake_agents = _types.SimpleNamespace(__file__=str(cwd / "agents" / "__init__.py"))
            old_cwd = Path.cwd()
            os_module = __import__("os")
            os_module.chdir(cwd)
            try:
                with mock.patch.dict(sys.modules, {"agents": fake_agents}):
                    check = _doctor.check_cwd_shadowing()
            finally:
                os_module.chdir(old_cwd)
        self.assertFalse(check.ok)
        self.assertIn("agents", check.detail)
        self.assertFalse(check.required)
