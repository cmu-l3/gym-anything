"""fast_io keyboard: modifier holds and text the uinput device cannot type.

fast_io composes a modifier-held gesture as keys_down, pointer action,
keys_up. Both fast keyboard backends must hold the key across the pointer
action; dropping the wrap silently performs the unmodified gesture.
"""

from __future__ import annotations

import base64
import re
import unittest
from unittest import mock

from gym_anything.runtime.runners import linux_uinput_fast_inputd as agent
from gym_anything.runtime.runners.qemu_apptainer import QemuApptainerRunner


class FastIoQmpKeyboardTests(unittest.TestCase):
    def _runner(self) -> QemuApptainerRunner:
        runner = QemuApptainerRunner.__new__(QemuApptainerRunner)
        runner._fast_io = True
        runner.is_android = False
        runner.is_windows = False
        return runner

    def test_qmp_backend_holds_and_releases_modifiers(self) -> None:
        runner = self._runner()
        sent = []

        with mock.patch.object(runner, "_qmp_send_input_events",
                               side_effect=lambda events: sent.extend(events)):
            runner._inject_action_via_qmp({"keyboard": {"keys_down": ["ctrl"]}})
            runner._inject_action_via_qmp({"keyboard": {"keys_up": ["ctrl"]}})

        self.assertEqual(
            sent,
            [{"type": "key", "data": {"down": True,
                                      "key": {"type": "qcode", "data": "ctrl"}}},
             {"type": "key", "data": {"down": False,
                                      "key": {"type": "qcode", "data": "ctrl"}}}],
        )

    def test_qmp_backend_accepts_a_bare_string_key(self) -> None:
        runner = self._runner()
        sent = []

        with mock.patch.object(runner, "_qmp_send_input_events",
                               side_effect=lambda events: sent.extend(events)):
            runner._inject_action_via_qmp({"keyboard": {"keys_down": "shift"}})

        self.assertEqual([event["data"]["key"]["data"] for event in sent], ["shift"])

    def test_unsupported_text_reroutes_to_the_guest_xlib_typer(self) -> None:
        """The uinput device cannot express characters outside the guest
        layout. Rerouting beats the two wrong answers: dropping them, or
        taking the episode down mid-action."""
        runner = self._runner()
        client = mock.Mock()
        client.request.return_value = {"ok": False, "error": "unsupported_text",
                                       "chars": ["ï"]}

        with mock.patch.object(runner, "_get_fast_input_client", return_value=client), \
                mock.patch.object(runner, "_run_guest_python") as guest:
            runner._inject_keyboard_via_fast_input_agent({"text": "naïve"})

        script = guest.call_args.args[0]
        encoded = re.search(r"b64decode\('([A-Za-z0-9+/=]+)'\)", script).group(1)
        self.assertIn("naïve", base64.b64decode(encoded).decode("utf-8"))

    def test_ascii_text_never_leaves_the_fast_path(self) -> None:
        runner = self._runner()
        client = mock.Mock()
        client.request.return_value = {"ok": True, "events": 4}

        with mock.patch.object(runner, "_get_fast_input_client", return_value=client), \
                mock.patch.object(runner, "_run_guest_python") as guest:
            runner._inject_keyboard_via_fast_input_agent({"text": "hi"})

        guest.assert_not_called()

    def test_unsupported_key_names_reroute_too(self) -> None:
        """Numpad and lock keys are outside the uinput map for the same
        reason accented characters are: the guest layout does not reach
        them. Same door, not a hard error."""
        runner = self._runner()
        client = mock.Mock()
        client.request.return_value = {"ok": False, "error": "unsupported_keys",
                                       "keys": ["kp_add"]}

        with mock.patch.object(runner, "_get_fast_input_client", return_value=client), \
                mock.patch.object(runner, "_run_guest_python") as guest:
            runner._inject_keyboard_via_fast_input_agent({"keys": ["kp_add"]})

        self.assertIn("kp_add", guest.call_args.args[0])

    def test_other_agent_errors_still_raise(self) -> None:
        runner = self._runner()
        client = mock.Mock()
        client.request.return_value = {"ok": False, "error": "device gone"}

        with mock.patch.object(runner, "_get_fast_input_client", return_value=client), \
                mock.patch.object(runner, "_run_guest_python"):
            with self.assertRaises(RuntimeError):
                runner._inject_keyboard_via_fast_input_agent({"text": "hi"})


class _FakeUInput:
    """Records what a real uinput device would have received."""

    name = "fake"

    def __init__(self) -> None:
        self.pressed: set = set()
        self.emitted: list = []

    def key_down(self, code: int) -> None:
        self.emitted.append(("down", code))
        self.pressed.add(code)

    def key_up(self, code: int) -> None:
        self.emitted.append(("up", code))
        self.pressed.discard(code)

    def key_tap(self, code: int) -> None:
        self.key_down(code)
        self.key_up(code)

    def combo(self, codes) -> None:
        codes = list(codes)
        for code in codes:
            self.key_down(code)
        for code in reversed(codes):
            self.key_up(code)

    def release_all(self) -> None:
        for code in sorted(self.pressed, reverse=True):
            self.emitted.append(("up", code))
        self.pressed.clear()


class FastInputAgentTests(unittest.TestCase):
    """The in-guest uinput agent, exercised against a fake device."""

    def _service(self, x11=None):
        device = _FakeUInput()
        return agent.FastInputService(device, x11, 500), device

    def test_keys_down_holds_across_requests(self) -> None:
        service, device = self._service()

        service.handle({"op": "keyboard", "keyboard": {"keys_down": ["ctrl"]}})
        self.assertEqual(device.pressed, {agent.KEY_BY_NAME["ctrl"]})

        service.handle({"op": "keyboard", "keyboard": {"keys_up": ["ctrl"]}})
        self.assertEqual(device.pressed, set())

    def test_unsupported_text_is_refused_without_touching_the_device(self) -> None:
        service, device = self._service()

        response = service.handle({"op": "keyboard", "keyboard": {"text": "naïve"}})

        self.assertFalse(response["ok"])
        self.assertEqual(response["error"], "unsupported_text")
        self.assertEqual(response["chars"], ["ï"])
        self.assertEqual(device.emitted, [])

    def test_unknown_key_names_are_refused_without_touching_the_device(self) -> None:
        service, device = self._service()

        response = service.handle({"op": "keyboard", "keyboard": {"keys": ["kp_add"]}})

        self.assertFalse(response["ok"])
        self.assertEqual(response["error"], "unsupported_keys")
        self.assertEqual(response["keys"], ["kp_add"])
        self.assertEqual(device.emitted, [])

    def test_a_chord_waits_for_each_key_before_pressing_the_next(self) -> None:
        """Measured on super+d: the tap saw key_down super, then key_down d
        with an empty modifier list, so the chord arrived as a bare d. ctrl+c
        registered fine, which is why pressing both and hoping looked correct
        for a long time."""
        x11 = mock.Mock()
        x11.keymap.return_value = b"\x00" * 32
        x11.wait_key_down.return_value = True
        service, device = self._service(x11=x11)

        service.handle({"op": "keyboard", "keyboard": {"keys": ["super", "d"]}})

        # one confirmation per key, in press order, before any release
        self.assertEqual([c.args[0] for c in x11.wait_key_down.call_args_list],
                         [agent.KEY_BY_NAME["super"] + 8,
                          agent.KEY_BY_NAME["d"] + 8])
        self.assertEqual(device.emitted[:2],
                         [("down", agent.KEY_BY_NAME["super"]),
                          ("down", agent.KEY_BY_NAME["d"])])

    def test_a_chord_key_the_server_never_registers_is_loud(self) -> None:
        x11 = mock.Mock()
        x11.keymap.return_value = b"\x00" * 32
        x11.wait_key_down.return_value = False
        service, device = self._service(x11=x11)

        with self.assertRaises(RuntimeError):
            service.handle({"op": "keyboard", "keyboard": {"keys": ["super", "d"]}})
        self.assertEqual(device.pressed, set())

    def test_a_held_key_is_acked_by_a_keymap_change_not_a_restore(self) -> None:
        """The old ack demanded the keymap return to its pre-action state,
        which is false by construction once a key is deliberately held."""
        x11 = mock.Mock()
        x11.keymap.return_value = b"\x00" * 32
        service, _device = self._service(x11=x11)

        service.handle({"op": "keyboard", "keyboard": {"keys_down": ["shift"]}})

        x11.wait_keymap_changed.assert_called_once()
        x11.wait_keymap_restored.assert_not_called()

    def test_a_balanced_request_is_still_acked_by_a_restore(self) -> None:
        x11 = mock.Mock()
        x11.keymap.return_value = b"\x00" * 32
        service, _device = self._service(x11=x11)

        service.handle({"op": "keyboard", "keyboard": {"keys": ["enter"]}})

        x11.wait_keymap_restored.assert_called_once()
        x11.wait_keymap_changed.assert_not_called()


if __name__ == "__main__":
    unittest.main()
