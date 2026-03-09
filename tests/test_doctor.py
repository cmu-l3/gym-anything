from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from gym_anything.doctor import render_doctor_text, run_doctor, scan_verifier_imports


class DoctorTests(unittest.TestCase):
    def test_run_doctor_reports_missing_docker_binary(self) -> None:
        with mock.patch("gym_anything.doctor.shutil.which", return_value=None):
            report = run_doctor(runner="docker")

        self.assertFalse(report.ok)
        self.assertTrue(any(check.name == "docker_cli" and not check.ok for check in report.checks))

    def test_run_doctor_accepts_local_runner_without_system_tools(self) -> None:
        report = run_doctor(runner="local")

        self.assertTrue(report.ok)
        self.assertEqual(report.checks[0].name, "local_runner")

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


if __name__ == "__main__":
    unittest.main()
