from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from gym_anything.runtime.runners.qemu_apptainer import QemuApptainerRunner


class QemuDbusFastIoTests(unittest.TestCase):
    def test_set_fast_io_prepares_dbus_container_only_for_dbus_backend(self) -> None:
        runner = QemuApptainerRunner.__new__(QemuApptainerRunner)
        runner._fast_io = False

        with mock.patch.dict(
            "os.environ",
            {"GYM_ANYTHING_QEMU_FAST_IO_BACKEND": "dbus"},
            clear=False,
        ), mock.patch.object(runner, "_ensure_dbus_display_container") as ensure:
            runner.set_fast_io(True)

        self.assertTrue(runner._fast_io)
        ensure.assert_called_once_with()

        with mock.patch.dict(
            "os.environ",
            {"GYM_ANYTHING_QEMU_FAST_IO_BACKEND": "qmp"},
            clear=False,
        ), mock.patch.object(runner, "_ensure_dbus_display_container") as ensure:
            runner.set_fast_io(True)

        ensure.assert_not_called()

    def test_dbus_container_uses_cached_sandbox_when_available(self) -> None:
        runner = QemuApptainerRunner.__new__(QemuApptainerRunner)
        runner._container_image = "docker://base"

        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp) / "dbus-sandbox"
            sandbox.mkdir()
            support_calls: list[str] = []

            def supports(container: str) -> bool:
                support_calls.append(container)
                return container == str(sandbox)

            with mock.patch.object(runner, "_dbus_sandbox_path", return_value=sandbox), \
                 mock.patch.object(runner, "_container_supports_dbus_display", side_effect=supports), \
                 mock.patch("subprocess.run") as run:
                runner._ensure_dbus_display_container()

        self.assertEqual(runner._container_image, str(sandbox))
        self.assertEqual(support_calls, [str(sandbox)])
        run.assert_not_called()

    def test_dbus_container_reports_missing_backend_when_auto_install_disabled(self) -> None:
        runner = QemuApptainerRunner.__new__(QemuApptainerRunner)
        runner._container_image = "docker://base"

        with mock.patch.dict(
            "os.environ",
            {"GYM_ANYTHING_QEMU_DBUS_AUTO_INSTALL": "0"},
            clear=False,
        ), mock.patch.object(runner, "_container_supports_dbus_display", return_value=False):
            with self.assertRaisesRegex(RuntimeError, "D-Bus display backend requested"):
                runner._ensure_dbus_display_container()


if __name__ == "__main__":
    unittest.main()
