"""Offline tests for GeminiComputerUseAgent's action translation.

The agent must handle BOTH Gemini computer-use vocabularies:
- legacy (gemini-3-flash-preview, gemini-2.5-computer-use-preview*):
  click_at / type_text_at / key_combination / scroll_at / ...
- current (gemini-3.5-flash): click / type / hotkey / press_key / scroll / ...

No API access needed: we build the agent without __init__ and call
_translate directly.
"""
import unittest
from pathlib import Path

from agents.agents.gemini_computer_use import (
    GeminiComputerUseAgent,
    _observation_frame_paths,
    _uses_legacy_actions,
)


def _bare_agent():
    agent = object.__new__(GeminiComputerUseAgent)
    agent.display_resolution = (1000, 1000)  # 0-999 coords map ~1:1 to pixels
    agent.pending_error = None
    agent.consecutive_unsupported = 0
    agent._last_unsupported = False
    return agent


class ModelFamilyTests(unittest.TestCase):
    def test_legacy_model_detection(self):
        self.assertTrue(_uses_legacy_actions("gemini-3-flash-preview"))
        self.assertTrue(_uses_legacy_actions("gemini-2.5-computer-use-preview-10-2025"))
        self.assertFalse(_uses_legacy_actions("gemini-3.5-flash"))


class ObservationSequenceTests(unittest.TestCase):
    def test_frames_take_precedence_and_keep_chronological_order(self):
        obs = {
            "screen": {"path": "latest.png"},
            "frames": [
                {"path": "first.png", "offset_ms": 0},
                {"path": "second.png", "offset_ms": 100},
            ],
        }
        self.assertEqual(
            _observation_frame_paths(obs),
            [Path("first.png"), Path("second.png")],
        )

    def test_screen_remains_the_single_frame_fallback(self):
        self.assertEqual(
            _observation_frame_paths({"screen": {"path": "latest.png"}}),
            [Path("latest.png")],
        )

    def test_function_response_contains_every_frame(self):
        agent = _bare_agent()
        response = agent._function_response("computer", "call-1", {}, [b"one", b"two"])
        self.assertEqual([part.inline_data.data for part in response.parts], [b"one", b"two"])


class LegacyVocabularyTests(unittest.TestCase):
    def setUp(self):
        self.agent = _bare_agent()

    def test_click_at(self):
        acts = self.agent._translate("click_at", {"x": 500, "y": 500})
        self.assertEqual(acts, [{"mouse": {"left_click": [500, 500]}}])

    def test_type_text_at_clicks_then_types(self):
        acts = self.agent._translate(
            "type_text_at",
            {"x": 100, "y": 200, "text": "hi", "clear_before_typing": True, "press_enter": True},
        )
        self.assertEqual(acts[0], {"mouse": {"left_click": [100, 200]}})
        self.assertEqual(acts[1], {"keyboard": {"keys": ["ctrl", "a"]}})
        self.assertEqual(acts[2], {"keyboard": {"text": "hi"}})
        self.assertEqual(acts[3], {"keyboard": {"keys": ["Return"]}})

    def test_key_combination_chord(self):
        acts = self.agent._translate("key_combination", {"keys": "ctrl+s"})
        self.assertEqual(acts, [{"keyboard": {"keys": ["ctrl", "s"]}}])

    def test_single_char_is_typed_not_keysym(self):
        acts = self.agent._translate("key_combination", {"keys": "+"})
        self.assertEqual(acts, [{"keyboard": {"text": "+"}}])

    def test_legacy_drag(self):
        acts = self.agent._translate(
            "drag_and_drop", {"x": 0, "y": 0, "destination_x": 999, "destination_y": 999})
        self.assertEqual(acts, [{"mouse": {"left_click_drag": [[0, 0], [999, 999]]}}])

    def test_wait_5_seconds(self):
        acts = self.agent._translate("wait_5_seconds", {})
        self.assertEqual(acts, [{"action": "wait", "time": 5}])


class NewVocabularyTests(unittest.TestCase):
    def setUp(self):
        self.agent = _bare_agent()

    def test_click_family(self):
        self.assertEqual(self.agent._translate("click", {"x": 10, "y": 20}),
                         [{"mouse": {"left_click": [10, 20]}}])
        self.assertEqual(self.agent._translate("right_click", {"x": 10, "y": 20}),
                         [{"mouse": {"right_click": [10, 20]}}])
        self.assertEqual(self.agent._translate("double_click", {"x": 10, "y": 20}),
                         [{"mouse": {"double_click": [10, 20]}}])
        self.assertEqual(self.agent._translate("triple_click", {"x": 10, "y": 20}),
                         [{"mouse": {"triple_click": [10, 20]}}])

    def test_type_at_focus_no_click(self):
        acts = self.agent._translate("type", {"text": "hello", "press_enter": True})
        self.assertEqual(acts, [{"keyboard": {"text": "hello"}},
                                {"keyboard": {"keys": ["Return"]}}])

    def test_press_key_named(self):
        acts = self.agent._translate("press_key", {"key": "enter"})
        self.assertEqual(acts, [{"keyboard": {"keys": ["Return"]}}])

    def test_hotkey_list(self):
        acts = self.agent._translate("hotkey", {"keys": ["ctrl", "shift", "p"]})
        self.assertEqual(acts, [{"keyboard": {"keys": ["ctrl", "shift", "p"]}}])

    def test_key_down_up(self):
        self.assertEqual(self.agent._translate("key_down", {"key": "shift"}),
                         [{"keyboard": {"keys_down": ["shift"]}}])
        self.assertEqual(self.agent._translate("key_up", {"key": "shift"}),
                         [{"keyboard": {"keys_up": ["shift"]}}])

    def test_scroll_with_coords_and_magnitude(self):
        acts = self.agent._translate(
            "scroll", {"x": 500, "y": 500, "direction": "down", "magnitude_in_pixels": 250})
        self.assertEqual(acts, [{"mouse": {"move": [500, 500]}},
                                {"mouse": {"scroll": -250}}])

    def test_new_drag_arg_names(self):
        acts = self.agent._translate(
            "drag_and_drop", {"start_x": 1, "start_y": 2, "end_x": 3, "end_y": 4})
        self.assertEqual(acts, [{"mouse": {"left_click_drag": [[1, 2], [3, 4]]}}])

    def test_take_screenshot(self):
        self.assertEqual(self.agent._translate("take_screenshot", {}),
                         [{"action": "screenshot"}])

    def test_wait_seconds(self):
        self.assertEqual(self.agent._translate("wait", {"seconds": 3}),
                         [{"action": "wait", "time": 3.0}])

    def test_long_press(self):
        acts = self.agent._translate("long_press", {"x": 5, "y": 5, "seconds": 2})
        self.assertEqual(acts[0], {"mouse": {"move": [5, 5]}})
        self.assertEqual(acts[1], {"mouse": {"buttons": {"left_down": True}}})
        self.assertEqual(acts[3], {"mouse": {"buttons": {"left_up": True}}})


class UnsupportedActionTests(unittest.TestCase):
    def setUp(self):
        self.agent = _bare_agent()

    def test_unknown_action_sets_error_and_counts(self):
        self.agent._translate("teleport", {})
        self.assertIn("teleport", self.agent.pending_error)
        self.assertEqual(self.agent.consecutive_unsupported, 1)

    def test_browser_navigation_reports_error(self):
        self.agent._translate("navigate", {"url": "https://x.test"})
        self.assertIn("navigate", self.agent.pending_error)
        self.assertEqual(self.agent.consecutive_unsupported, 1)

    def test_horizontal_scroll_counts_as_unsupported(self):
        self.agent._translate("scroll", {"x": 1, "y": 1, "direction": "left"})
        self.assertEqual(self.agent.consecutive_unsupported, 1)

    def test_successful_action_resets_counter(self):
        self.agent._translate("teleport", {})
        self.agent._translate("teleport", {})
        self.assertEqual(self.agent.consecutive_unsupported, 2)
        self.agent._translate("click", {"x": 1, "y": 1})
        self.assertEqual(self.agent.consecutive_unsupported, 0)


if __name__ == "__main__":
    unittest.main()
