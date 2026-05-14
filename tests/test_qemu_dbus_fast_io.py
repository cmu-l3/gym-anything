from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from gym_anything.runtime.runners.qemu_apptainer import QemuApptainerRunner


class QemuDbusFastIoTests(unittest.TestCase):
    def _runner(self) -> QemuApptainerRunner:
        runner = QemuApptainerRunner.__new__(QemuApptainerRunner)
        runner.resolution = (1920, 1080)
        runner.is_android = False
        runner.is_windows = False
        runner._fast_io = True
        return runner

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

    def test_fast_qmp_input_uses_absolute_pointer_coordinates(self) -> None:
        runner = self._runner()

        with mock.patch.object(runner, "_qmp_send_input_events") as send:
            runner._inject_action_via_qmp({"mouse": {"move": [1919, 1079]}})

        events = send.call_args.args[0]
        self.assertEqual(events[0], {"type": "abs", "data": {"axis": "x", "value": 0x7FFF}})
        self.assertEqual(events[1], {"type": "abs", "data": {"axis": "y", "value": 0x7FFF}})

    def test_fast_qmp_input_encodes_clicks_scroll_and_drag(self) -> None:
        runner = self._runner()

        with mock.patch.object(runner, "_qmp_send_input_events") as send:
            runner._inject_action_via_qmp(
                {
                    "mouse": {
                        "left_click": [100, 200],
                        "scroll": -2,
                        "left_click_drag": [[10, 20], [90, 100]],
                    }
                }
            )

        event_batches = [call.args[0] for call in send.call_args_list]
        self.assertEqual(event_batches[0][0]["type"], "abs")
        self.assertEqual(event_batches[0][1]["type"], "abs")
        self.assertEqual(event_batches[1], [{"type": "btn", "data": {"down": True, "button": "left"}}])
        self.assertEqual(event_batches[2], [{"type": "btn", "data": {"down": False, "button": "left"}}])
        events = [event for batch in event_batches for event in batch]
        buttons = [event["data"]["button"] for event in events if event["type"] == "btn"]
        self.assertEqual(buttons[:2], ["left", "left"])
        self.assertEqual(buttons[2:4], ["left", "left"])
        self.assertEqual(buttons[4:], ["wheel-up", "wheel-up", "wheel-up", "wheel-up"])
        self.assertGreaterEqual(sum(1 for event in events if event["type"] == "abs"), 18)

    def test_fast_qmp_input_encodes_text_and_hotkey(self) -> None:
        runner = self._runner()

        with mock.patch.object(runner, "_qmp_send_input_events") as send:
            runner._inject_action_via_qmp({"keyboard": {"text": "Az!\n", "keys": ["ctrl", "a"]}})

        events = []
        for call in send.call_args_list:
            events.extend(call.args[0])
        key_events = [event["data"] for event in events if event["type"] == "key"]
        qcodes = [event["key"]["data"] for event in key_events]
        self.assertIn("shift", qcodes)
        self.assertIn("a", qcodes)
        self.assertIn("z", qcodes)
        self.assertIn("1", qcodes)
        self.assertIn("ret", qcodes)
        self.assertEqual(qcodes[-4:], ["ctrl", "a", "a", "ctrl"])

    def test_inject_action_uses_qmp_when_fast_io_is_enabled(self) -> None:
        runner = self._runner()

        with mock.patch.object(runner, "_inject_action_via_qmp") as inject:
            runner.inject_action({"mouse": {"move": [1, 2]}})

        inject.assert_called_once_with({"mouse": {"move": [1, 2]}})


if __name__ == "__main__":
    unittest.main()
