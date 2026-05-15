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
        runner._fast_input_host_port = None
        runner._fast_input_guest_port = 5599
        runner._fast_input_device_name = "GymAnything Fast Keyboard"
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

        with mock.patch.object(runner, "_qmp_send_key_combo") as send:
            runner._inject_action_via_qmp({"keyboard": {"text": "Az!\n", "keys": ["ctrl", "a"]}})

        qcode_groups = [call.args[0] for call in send.call_args_list]
        self.assertEqual(qcode_groups[:4], [["shift", "a"], ["z"], ["shift", "1"], ["ret"]])
        self.assertEqual(qcode_groups[-1], ["ctrl", "a"])

    def test_fast_qmp_keyboard_uses_experimental_send_key_pacing(self) -> None:
        runner = self._runner()
        client = mock.Mock()

        with mock.patch.object(runner, "_get_qmp_client", return_value=client), \
             mock.patch("gym_anything.runtime.runners.qemu_apptainer.time.sleep") as sleep:
            runner._qmp_send_key_combo(["ctrl", "a"])

        client.execute.assert_called_once_with(
            "send-key",
            {
                "keys": [
                    {"type": "qcode", "data": "ctrl"},
                    {"type": "qcode", "data": "a"},
                ],
                "hold-time": 5,
            },
        )
        sleep.assert_called_once_with(0.010)

    def test_fast_qmp_keyboard_pacing_can_be_overridden(self) -> None:
        runner = self._runner()
        client = mock.Mock()

        with mock.patch.dict(
            "os.environ",
            {
                "GYM_ANYTHING_QEMU_QMP_KEY_HOLD_MS": "12",
                "GYM_ANYTHING_QEMU_QMP_KEY_GAP_MS": "34",
            },
            clear=False,
        ), mock.patch.object(runner, "_get_qmp_client", return_value=client), \
             mock.patch("gym_anything.runtime.runners.qemu_apptainer.time.sleep") as sleep:
            runner._qmp_send_key_combo(["ret"])

        self.assertEqual(client.execute.call_args.args[1]["hold-time"], 12)
        sleep.assert_called_once_with(0.034)

    def test_fast_qmp_keyboard_pacing_rejects_invalid_values(self) -> None:
        runner = self._runner()

        with mock.patch.dict("os.environ", {"GYM_ANYTHING_QEMU_QMP_KEY_HOLD_MS": "-1"}, clear=False):
            with self.assertRaisesRegex(RuntimeError, "GYM_ANYTHING_QEMU_QMP_KEY_HOLD_MS"):
                runner._qmp_experimental_key_hold_ms()

        with mock.patch.dict("os.environ", {"GYM_ANYTHING_QEMU_QMP_KEY_GAP_MS": "slow"}, clear=False):
            with self.assertRaisesRegex(RuntimeError, "GYM_ANYTHING_QEMU_QMP_KEY_GAP_MS"):
                runner._qmp_experimental_key_gap_seconds()

    def test_fast_qmp_text_key_groups_encode_shifted_characters(self) -> None:
        runner = self._runner()

        self.assertEqual(
            runner._qmp_text_key_groups("Az!\n"),
            [["shift", "a"], ["z"], ["shift", "1"], ["ret"]],
        )

    def test_inject_action_uses_qmp_for_mouse_when_fast_io_is_enabled(self) -> None:
        runner = self._runner()

        with mock.patch.object(runner, "_inject_action_via_qmp") as inject:
            runner.inject_action({"mouse": {"move": [1, 2]}})

        inject.assert_called_once_with({"mouse": {"move": [1, 2]}})

    def test_inject_action_uses_uinput_agent_for_linux_fast_keyboard(self) -> None:
        runner = self._runner()

        with mock.patch.object(runner, "_inject_action_via_qmp") as qmp, \
             mock.patch.object(runner, "_inject_keyboard_via_fast_input_agent") as keyboard:
            runner.inject_action({"keyboard": {"text": "abc"}})

        qmp.assert_not_called()
        keyboard.assert_called_once_with({"text": "abc"})

    def test_explicit_qmp_experimental_keyboard_backend_uses_qmp(self) -> None:
        runner = self._runner()

        with mock.patch.dict("os.environ", {"GYM_ANYTHING_QEMU_FAST_KEYBOARD_BACKEND": "qmp-experimental"}, clear=False), \
             mock.patch.object(runner, "_inject_action_via_qmp") as qmp, \
             mock.patch.object(runner, "_inject_keyboard_via_fast_input_agent") as keyboard:
            runner.inject_action({"keyboard": {"text": "abc"}})

        qmp.assert_called_once_with({"keyboard": {"text": "abc"}})
        keyboard.assert_not_called()

    def test_invalid_linux_fast_keyboard_backend_fails_loudly(self) -> None:
        runner = self._runner()

        with mock.patch.dict("os.environ", {"GYM_ANYTHING_QEMU_FAST_KEYBOARD_BACKEND": "unknown"}, clear=False):
            with self.assertRaisesRegex(RuntimeError, "Unsupported QEMU fast keyboard backend"):
                runner.set_fast_io(True)

    def test_linux_fast_io_qemu_command_adds_usb_hid_devices(self) -> None:
        runner = self._runner()
        runner.memory = "8G"
        runner.cpus = 4
        runner.enable_kvm = False
        runner._fast_input_host_port = 45678
        runner._build_container_prefix = lambda work_dir, disk: []

        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            cmd = runner._build_qemu_cmd(
                work_dir / "disk.qcow2",
                vnc_port=5901,
                ssh_port=2222,
                work_dir=work_dir,
            )

        self.assertIn("qemu-xhci,id=fastio_xhci", cmd)
        self.assertIn("usb-kbd,id=fastio_kbd,bus=fastio_xhci.0", cmd)
        self.assertIn("usb-tablet,id=fastio_tablet,bus=fastio_xhci.0", cmd)
        self.assertIn("user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::45678-:5599", cmd)

    def test_linux_non_fast_io_qemu_command_keeps_legacy_input_devices(self) -> None:
        runner = self._runner()
        runner._fast_io = False
        runner.memory = "8G"
        runner.cpus = 4
        runner.enable_kvm = False
        runner._build_container_prefix = lambda work_dir, disk: []

        with tempfile.TemporaryDirectory() as tmp:
            work_dir = Path(tmp)
            cmd = runner._build_qemu_cmd(
                work_dir / "disk.qcow2",
                vnc_port=5901,
                ssh_port=2222,
                work_dir=work_dir,
            )

        self.assertNotIn("qemu-xhci,id=fastio_xhci", cmd)
        self.assertNotIn("usb-kbd,id=fastio_kbd,bus=fastio_xhci.0", cmd)
        self.assertNotIn("usb-tablet,id=fastio_tablet,bus=fastio_xhci.0", cmd)


if __name__ == "__main__":
    unittest.main()
