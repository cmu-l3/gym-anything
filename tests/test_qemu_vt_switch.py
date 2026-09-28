"""QEMU drops Ctrl+Alt+F<n>: on a Linux guest it switches to a text console,
X gets no more input, and the screen shows "login:" for the rest of the
episode."""

from __future__ import annotations

import unittest
from unittest import mock

from gym_anything.runtime.runners.qemu_apptainer import QemuApptainerRunner


class VTSwitchTests(unittest.TestCase):
    def _runner(self, fast_io=True, windows=False) -> QemuApptainerRunner:
        runner = QemuApptainerRunner.__new__(QemuApptainerRunner)
        runner._fast_io = fast_io
        runner.is_android = False
        runner.is_windows = windows
        runner._pyautogui_client = None
        return runner

    def test_vt_switch_chords_are_dropped_on_every_linux_path(self) -> None:
        chords = [
            {"keys": ["ctrl", "alt", "f4"]},
            {"keys": ["Control_L", "Alt_R", "F12"]},
            {"keys": ["leftctrl", "leftalt", "f1"]},
            {"keys_down": ["ctrl", "alt", "f2"]},
            {"keys": ["Meta_L", "Control_L", "F1"]},
        ]
        for fast_io in (True, False):
            for keyboard in chords:
                runner = self._runner(fast_io=fast_io)
                with mock.patch.object(runner, "_inject_action_via_fast_io") as fast, \
                        mock.patch.object(runner, "_run_guest_python") as slow, \
                        mock.patch.object(runner, "_run_pyautogui") as mouse:
                    runner.inject_action({"mouse": {"left_click": [1, 2]}, "keyboard": keyboard})
                slow.assert_not_called()
                if fast_io:
                    fast.assert_called_once_with({"mouse": {"left_click": [1, 2]}})
                else:
                    mouse.assert_called_once()

    def test_keys_up_in_the_same_action_still_goes_through(self) -> None:
        runner = self._runner()
        with mock.patch.object(runner, "_inject_action_via_fast_io") as fast:
            runner.inject_action({"keyboard": {"keys": ["ctrl", "alt", "f4"], "keys_up": ["shift"]}})
        fast.assert_called_once_with({"keyboard": {"keys_up": ["shift"]}})

    def test_other_chords_pass(self) -> None:
        for keyboard in ({"keys": ["alt", "f4"]}, {"keys": ["ctrl", "alt", "t"]},
                         {"keys": "f5"}, {"text": "ctrl alt f4"}):
            runner = self._runner()
            with mock.patch.object(runner, "_inject_action_via_fast_io") as fast:
                runner.inject_action({"keyboard": keyboard})
            fast.assert_called_once_with({"keyboard": keyboard})

    def test_windows_guests_keep_the_chord(self) -> None:
        runner = self._runner(windows=True)
        action = {"keyboard": {"keys": ["ctrl", "alt", "f4"]}}
        with mock.patch.object(runner, "_inject_action_via_fast_io") as fast:
            runner.inject_action(action)
        fast.assert_called_once_with(action)


if __name__ == "__main__":
    unittest.main()
