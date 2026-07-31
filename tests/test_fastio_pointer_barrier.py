"""fast_io pointer injection confirms delivery instead of assuming it.

QMP's input-send-event returns once QEMU has QUEUED events into the virtio
device, which says nothing about the guest consuming them. Measured
consequences of assuming it: a keyboard release injected in-guest overtakes a
queued click so the modifier arrives dropped, a second click lands before the
first is seen so repeats collapse, and a batch of moves latches only its last
coordinate so a drag presses at its own endpoint.
"""

from __future__ import annotations

import unittest
from unittest import mock

from gym_anything.runtime.runners.qemu_apptainer import _X_BUTTON_MASK, QemuApptainerRunner


class PointerBarrierTests(unittest.TestCase):
    def _runner(self, acks: bool = True):
        runner = QemuApptainerRunner.__new__(QemuApptainerRunner)
        runner._fast_io = True
        runner.is_android = False
        runner.is_windows = False
        runner.resolution = (1920, 1080)
        client = mock.Mock()
        client.request.return_value = {"ok": True, "matched": True,
                                       "x": 0, "y": 0, "mask": 0}
        runner._get_fast_input_client = mock.Mock(return_value=client)
        runner._fast_uinput_keyboard_enabled = mock.Mock(return_value=acks)
        runner._fast_input_host_port = 45500 if acks else None
        return runner, client

    @staticmethod
    def _expects(client):
        return [call.args[0]["expect"] for call in client.request.call_args_list
                if call.args[0].get("op") == "await_pointer"]

    def test_a_click_waits_for_the_press_and_the_release(self) -> None:
        runner, client = self._runner()
        with mock.patch.object(runner, "_qmp_send_input_events"):
            runner._inject_action_via_qmp({"mouse": {"left_click": [400, 300]}})

        self.assertEqual(
            self._expects(client),
            [{"x": 400, "y": 300},
             {"mask_set": _X_BUTTON_MASK["left"]},
             {"mask_clear": _X_BUTTON_MASK["left"]}],
        )

    def test_a_double_click_waits_between_the_two_presses(self) -> None:
        """Without a barrier between them the guest saw one press, not two."""
        runner, client = self._runner()
        with mock.patch.object(runner, "_qmp_send_input_events"):
            runner._inject_action_via_qmp({"mouse": {"double_click": [10, 20]}})

        masks = [e for e in self._expects(client) if "mask_set" in e]
        self.assertEqual(len(masks), 2)

    def test_scroll_rides_the_same_device_as_the_keys(self) -> None:
        """A modifier-held scroll is keys_down, scroll, keys_up. Sent through
        QEMU while the keys go in-guest, the release overtook the notches and
        the app saw an unmodified scroll. One device, one order."""
        runner, client = self._runner()
        sends = []
        with mock.patch.object(runner, "_qmp_send_input_events",
                               side_effect=lambda events: sends.append(list(events))):
            runner._inject_action_via_qmp({"mouse": {"scroll": 3}})

        self.assertEqual(sends, [])          # nothing went through QEMU
        scrolls = [c.args[0] for c in client.request.call_args_list
                   if c.args[0].get("op") == "scroll"]
        self.assertEqual(scrolls, [{"op": "scroll", "dy": 3, "dx": 0}])

    def test_each_scroll_tick_is_its_own_send_and_is_not_acked(self) -> None:
        """Batched into one input-send-event the guest coalesced them and 25
        requested ticks arrived as 24, so each tick is sent on its own. It is
        not acked: QEMU turns a wheel btn into REL_WHEEL, so no wheel button
        is ever held and XQueryPointer's mask can never show one. Waiting for
        that state fails every scroll."""
        runner, client = self._runner(acks=False)
        sends = []
        with mock.patch.object(runner, "_qmp_send_input_events",
                               side_effect=lambda events: sends.append(list(events))):
            runner._inject_action_via_qmp({"mouse": {"scroll": 5}})

        self.assertEqual(len(sends), 10)          # press and release, per tick
        self.assertTrue(all(len(batch) == 1 for batch in sends))
        self.assertEqual(self._expects(client), [])

    def test_a_drag_waits_at_every_waypoint(self) -> None:
        runner, client = self._runner()
        with mock.patch.object(runner, "_qmp_send_input_events"):
            runner._inject_action_via_qmp(
                {"mouse": {"left_click_drag": [[0, 0], [80, 80]]}})

        expects = self._expects(client)
        positions = [e for e in expects if "x" in e]
        # start, the press at the start, then one per waypoint
        self.assertEqual(len(positions), 2 + runner._QMP_DRAG_STEPS)
        self.assertEqual(positions[-1], {"x": 80, "y": 80})
        self.assertEqual(expects[-1], {"mask_clear": _X_BUTTON_MASK["left"]})

    def test_an_undelivered_event_raises_instead_of_passing_silently(self) -> None:
        runner, client = self._runner()
        client.request.return_value = {"ok": True, "matched": False,
                                       "x": 1, "y": 2, "mask": 0}
        with mock.patch.object(runner, "_qmp_send_input_events"):
            with self.assertRaises(RuntimeError) as caught:
                runner._inject_action_via_qmp({"mouse": {"move": [400, 300]}})
        self.assertIn("never reached the guest X server", str(caught.exception))

    def test_without_the_in_guest_agent_there_is_no_barrier_to_use(self) -> None:
        runner, client = self._runner(acks=False)
        with mock.patch.object(runner, "_qmp_send_input_events"):
            runner._inject_action_via_qmp({"mouse": {"left_click": [1, 2]}})
        self.assertEqual(self._expects(client), [])

    def test_a_repeated_move_still_produces_a_motion_event(self) -> None:
        """Every action in the vocabulary produces its own events. An absolute
        device is silent when asked for the position it already holds, which
        made a repeated move the one action whose observability depended on
        what happened before it."""
        runner, client = self._runner()
        client.request.return_value = {"ok": True, "matched": True,
                                       "x": 400, "y": 300, "mask": 0}
        with mock.patch.object(runner, "_qmp_send_input_events"):
            runner._inject_action_via_qmp({"mouse": {"move": [400, 300]}})

        moves = [e for e in self._expects(client) if "x" in e]
        # far enough to clear both the ack tolerance and the mapping's rounding
        self.assertEqual(moves, [{"x": 392, "y": 300}, {"x": 400, "y": 300}])

    def test_a_move_somewhere_new_does_not_detour(self) -> None:
        runner, client = self._runner()
        client.request.return_value = {"ok": True, "matched": True,
                                       "x": 10, "y": 10, "mask": 0}
        with mock.patch.object(runner, "_qmp_send_input_events"):
            runner._inject_action_via_qmp({"mouse": {"move": [400, 300]}})

        moves = [e for e in self._expects(client) if "x" in e]
        self.assertEqual(moves, [{"x": 400, "y": 300}])

    def test_the_runner_reports_whether_it_acks_delivery(self) -> None:
        runner, _client = self._runner()
        self.assertTrue(runner.acks_input_delivery())
        runner._fast_io = False
        self.assertFalse(runner.acks_input_delivery())


if __name__ == "__main__":
    unittest.main()
