"""Unit tests for gym_anything.installers.

Covers InstallStep, InstallPlan, get_install_plan, and run_install_plan.
All subprocess and shutil.which calls are mocked so tests are hermetic.
"""
from __future__ import annotations

import unittest
from unittest import mock

from gym_anything.installers import (
    InstallPlan,
    InstallStep,
    get_install_plan,
    run_install_plan,
)


# ---------------------------------------------------------------------------
# InstallStep
# ---------------------------------------------------------------------------


class TestInstallStep(unittest.TestCase):
    def _make_step(self, *, skip_if: str | None = None, requires: list[str] | None = None) -> InstallStep:
        return InstallStep(
            description="Install foo",
            command=["brew", "install", "foo"],
            requires=requires or [],
            skip_if=skip_if,
        )

    def test_should_skip_when_binary_present(self) -> None:
        step = self._make_step(skip_if="foo")
        with mock.patch("gym_anything.installers.shutil.which", return_value="/usr/bin/foo"):
            self.assertTrue(step.should_skip())

    def test_should_not_skip_when_binary_absent(self) -> None:
        step = self._make_step(skip_if="foo")
        with mock.patch("gym_anything.installers.shutil.which", return_value=None):
            self.assertFalse(step.should_skip())

    def test_should_not_skip_when_skip_if_is_none(self) -> None:
        step = self._make_step(skip_if=None)
        # No which call needed; skip_if is None → never skip
        self.assertFalse(step.should_skip())

    def test_missing_prereqs_empty_when_all_present(self) -> None:
        step = self._make_step(requires=["brew", "curl"])
        with mock.patch("gym_anything.installers.shutil.which", return_value="/usr/bin/x"):
            missing = step.missing_prereqs()
        self.assertEqual(missing, [])

    def test_missing_prereqs_lists_absent_binaries(self) -> None:
        step = self._make_step(requires=["brew", "sudo"])
        def which_side(name: str) -> str | None:
            return "/bin/sudo" if name == "sudo" else None
        with mock.patch("gym_anything.installers.shutil.which", side_effect=which_side):
            missing = step.missing_prereqs()
        self.assertEqual(missing, ["brew"])

    def test_render_returns_space_joined_command(self) -> None:
        step = InstallStep(description="x", command=["brew", "install", "vfkit"])
        self.assertEqual(step.render(), "brew install vfkit")

    def test_render_shell_step_returns_command_string(self) -> None:
        cmd = "curl -fsSL https://get.docker.com | sh"
        step = InstallStep(description="install docker", command=[cmd], shell=True)
        self.assertEqual(step.render(), cmd)

    def test_frozen_step_is_immutable(self) -> None:
        step = self._make_step()
        with self.assertRaises((AttributeError, TypeError)):
            step.description = "changed"  # type: ignore[misc]


# ---------------------------------------------------------------------------
# InstallPlan
# ---------------------------------------------------------------------------


class TestInstallPlan(unittest.TestCase):
    def test_plan_fields_accessible(self) -> None:
        plan = InstallPlan(runner="docker", summary="Docker Engine")
        self.assertEqual(plan.runner, "docker")
        self.assertEqual(plan.summary, "Docker Engine")
        self.assertEqual(plan.steps, [])
        self.assertIsNone(plan.prereq_note)
        self.assertIsNone(plan.manual_only)

    def test_plan_with_steps(self) -> None:
        step = InstallStep(description="install", command=["brew", "install", "vfkit"])
        plan = InstallPlan(runner="avf", summary="AVF", steps=[step])
        self.assertEqual(len(plan.steps), 1)
        self.assertEqual(plan.steps[0].description, "install")

    def test_plan_with_manual_only(self) -> None:
        plan = InstallPlan(
            runner="qemu",
            summary="Apptainer via cluster modules",
            manual_only="module load apptainer",
        )
        self.assertIsNotNone(plan.manual_only)
        self.assertIn("apptainer", plan.manual_only)

    def test_frozen_plan_is_immutable(self) -> None:
        plan = InstallPlan(runner="docker", summary="x")
        with self.assertRaises((AttributeError, TypeError)):
            plan.runner = "avf"  # type: ignore[misc]


# ---------------------------------------------------------------------------
# get_install_plan
# ---------------------------------------------------------------------------


class TestGetInstallPlan(unittest.TestCase):
    def test_returns_none_for_unknown_runner(self) -> None:
        plan = get_install_plan("nonexistent_runner")
        self.assertIsNone(plan)

    def test_returns_none_for_empty_string(self) -> None:
        self.assertIsNone(get_install_plan(""))

    def test_docker_plan_on_macos(self) -> None:
        with mock.patch("gym_anything.installers._IS_MACOS", True), \
                mock.patch("gym_anything.installers._IS_LINUX", False):
            plan = get_install_plan("docker")
        self.assertIsNotNone(plan)
        assert plan is not None
        self.assertEqual(plan.runner, "docker")
        self.assertIn("Docker", plan.summary)

    def test_docker_plan_on_linux(self) -> None:
        with mock.patch("gym_anything.installers._IS_MACOS", False), \
                mock.patch("gym_anything.installers._IS_LINUX", True):
            plan = get_install_plan("docker")
        self.assertIsNotNone(plan)
        assert plan is not None
        self.assertEqual(plan.runner, "docker")
        # Linux plan uses get.docker.com
        all_commands = " ".join(step.render() for step in plan.steps)
        self.assertIn("get.docker.com", all_commands)

    def test_avf_plan_on_macos_arm(self) -> None:
        with mock.patch("gym_anything.installers._IS_MACOS", True), \
                mock.patch("gym_anything.installers._IS_ARM", True):
            plan = get_install_plan("avf")
        self.assertIsNotNone(plan)
        assert plan is not None
        self.assertEqual(plan.runner, "avf")
        step_names = [s.description for s in plan.steps]
        self.assertTrue(any("vfkit" in n.lower() for n in step_names))

    def test_avf_plan_includes_gvproxy_step(self) -> None:
        with mock.patch("gym_anything.installers._IS_MACOS", True), \
                mock.patch("gym_anything.installers._IS_ARM", False):
            plan = get_install_plan("avf")
        self.assertIsNotNone(plan)
        assert plan is not None
        all_renders = " ".join(step.render() for step in plan.steps)
        self.assertIn("gvproxy", all_renders)

    def test_qemu_native_plan_on_macos(self) -> None:
        with mock.patch("gym_anything.installers._IS_MACOS", True):
            plan = get_install_plan("qemu_native")
        self.assertIsNotNone(plan)
        assert plan is not None
        self.assertEqual(plan.runner, "qemu_native")

    def test_qemu_plan_returned_on_linux_with_conda(self) -> None:
        with mock.patch("gym_anything.installers._IS_MACOS", False), \
                mock.patch("gym_anything.installers._IS_LINUX", True), \
                mock.patch("gym_anything.installers.shutil.which", side_effect=lambda b: "/usr/bin/conda" if b == "conda" else None), \
                mock.patch("gym_anything.installers._has_module_system", return_value=False):
            plan = get_install_plan("qemu")
        self.assertIsNotNone(plan)
        assert plan is not None
        self.assertEqual(plan.runner, "qemu")
        # conda path → plan has steps (not manual-only)
        self.assertIsNone(plan.manual_only)
        all_commands = " ".join(step.render() for step in plan.steps)
        self.assertIn("conda", all_commands)

    def test_qemu_plan_manual_only_on_hpc_with_module(self) -> None:
        with mock.patch("gym_anything.installers._IS_MACOS", False), \
                mock.patch("gym_anything.installers._IS_LINUX", True), \
                mock.patch("gym_anything.installers._module_has_apptainer", return_value=True):
            plan = get_install_plan("qemu")
        self.assertIsNotNone(plan)
        assert plan is not None
        self.assertIsNotNone(plan.manual_only)
        self.assertIn("module load", plan.manual_only)

    def test_qemu_plan_apt_on_debian_no_conda(self) -> None:
        def which_side(b: str) -> str | None:
            if b == "apt-get":
                return "/usr/bin/apt-get"
            return None
        with mock.patch("gym_anything.installers._IS_MACOS", False), \
                mock.patch("gym_anything.installers._IS_LINUX", True), \
                mock.patch("gym_anything.installers._has_module_system", return_value=False), \
                mock.patch("gym_anything.installers._module_has_apptainer", return_value=False), \
                mock.patch("gym_anything.installers.shutil.which", side_effect=which_side):
            plan = get_install_plan("qemu")
        self.assertIsNotNone(plan)
        assert plan is not None
        self.assertIsNone(plan.manual_only)
        all_commands = " ".join(step.render() for step in plan.steps)
        self.assertIn("apt-get", all_commands)

    def test_qemu_plan_manual_only_fallback_no_tools(self) -> None:
        with mock.patch("gym_anything.installers._IS_MACOS", False), \
                mock.patch("gym_anything.installers._IS_LINUX", True), \
                mock.patch("gym_anything.installers._has_module_system", return_value=False), \
                mock.patch("gym_anything.installers._module_has_apptainer", return_value=False), \
                mock.patch("gym_anything.installers.shutil.which", return_value=None):
            plan = get_install_plan("qemu")
        self.assertIsNotNone(plan)
        assert plan is not None
        self.assertIsNotNone(plan.manual_only)
        self.assertIn("apptainer.org", plan.manual_only)


# ---------------------------------------------------------------------------
# run_install_plan
# ---------------------------------------------------------------------------


class TestRunInstallPlan(unittest.TestCase):
    def _simple_step(self, skip_if: str | None = None, requires: list[str] | None = None) -> InstallStep:
        return InstallStep(
            description="install foo",
            command=["brew", "install", "foo"],
            skip_if=skip_if,
            requires=requires or [],
        )

    def test_dry_run_skips_execution(self) -> None:
        step = self._simple_step()
        plan = InstallPlan(runner="test", summary="test", steps=[step])
        with mock.patch("gym_anything.installers.shutil.which", return_value=None), \
                mock.patch("gym_anything.installers.subprocess.run") as mock_run:
            result = run_install_plan(plan, dry_run=True)
        # dry_run=True should not call subprocess.run
        mock_run.assert_not_called()
        self.assertTrue(result)

    def test_successful_step_returns_true(self) -> None:
        step = self._simple_step()
        plan = InstallPlan(runner="test", summary="test", steps=[step])
        with mock.patch("gym_anything.installers.shutil.which", return_value=None), \
                mock.patch("gym_anything.installers.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0)
            result = run_install_plan(plan)
        self.assertTrue(result)

    def test_failed_step_returns_false(self) -> None:
        step = self._simple_step()
        plan = InstallPlan(runner="test", summary="test", steps=[step])
        with mock.patch("gym_anything.installers.shutil.which", return_value=None), \
                mock.patch("gym_anything.installers.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=1)
            result = run_install_plan(plan)
        self.assertFalse(result)

    def test_step_skipped_when_binary_present(self) -> None:
        step = self._simple_step(skip_if="foo")
        plan = InstallPlan(runner="test", summary="test", steps=[step])
        with mock.patch("gym_anything.installers.shutil.which", return_value="/usr/bin/foo"), \
                mock.patch("gym_anything.installers.subprocess.run") as mock_run:
            result = run_install_plan(plan)
        mock_run.assert_not_called()
        self.assertTrue(result)

    def test_missing_prereq_causes_failure(self) -> None:
        step = self._simple_step(requires=["brew"])
        plan = InstallPlan(runner="test", summary="test", steps=[step])
        # brew not found → step should fail before subprocess call
        with mock.patch("gym_anything.installers.shutil.which", return_value=None), \
                mock.patch("gym_anything.installers.subprocess.run") as mock_run:
            result = run_install_plan(plan)
        mock_run.assert_not_called()
        self.assertFalse(result)

    def test_empty_plan_succeeds(self) -> None:
        plan = InstallPlan(runner="test", summary="nothing to do", steps=[])
        result = run_install_plan(plan)
        self.assertTrue(result)

    def test_shell_step_uses_shell_true(self) -> None:
        cmd = "curl -fsSL https://get.docker.com | sh"
        step = InstallStep(description="install docker", command=[cmd], shell=True)
        plan = InstallPlan(runner="docker", summary="Docker", steps=[step])
        with mock.patch("gym_anything.installers.shutil.which", return_value=None), \
                mock.patch("gym_anything.installers.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0)
            result = run_install_plan(plan)
        call_kwargs = mock_run.call_args
        self.assertTrue(call_kwargs[1].get("shell") or (len(call_kwargs[0]) > 1 and call_kwargs[0][1] is True) or "shell=True" in str(call_kwargs))
        self.assertTrue(result)

    def test_keyboard_interrupt_returns_false(self) -> None:
        step = self._simple_step()
        plan = InstallPlan(runner="test", summary="test", steps=[step])
        with mock.patch("gym_anything.installers.shutil.which", return_value=None), \
                mock.patch("gym_anything.installers.subprocess.run", side_effect=KeyboardInterrupt):
            result = run_install_plan(plan)
        self.assertFalse(result)

    def test_multiple_steps_all_succeed(self) -> None:
        steps = [
            self._simple_step(),
            InstallStep(description="install bar", command=["brew", "install", "bar"]),
        ]
        plan = InstallPlan(runner="test", summary="test", steps=steps)
        with mock.patch("gym_anything.installers.shutil.which", return_value=None), \
                mock.patch("gym_anything.installers.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0)
            result = run_install_plan(plan)
        self.assertEqual(mock_run.call_count, 2)
        self.assertTrue(result)

    def test_second_step_not_run_after_first_fails(self) -> None:
        steps = [
            self._simple_step(),
            InstallStep(description="install bar", command=["brew", "install", "bar"]),
        ]
        plan = InstallPlan(runner="test", summary="test", steps=steps)
        with mock.patch("gym_anything.installers.shutil.which", return_value=None), \
                mock.patch("gym_anything.installers.subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=1)
            result = run_install_plan(plan)
        # Should stop after first failure
        self.assertEqual(mock_run.call_count, 1)
        self.assertFalse(result)


if __name__ == "__main__":
    unittest.main()
