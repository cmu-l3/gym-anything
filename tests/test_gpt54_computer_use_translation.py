"""Offline tests for GPT54ComputerUseAgent's action translation.

The OpenAI Responses API computer tool returns batched actions per
computer_call; each action may carry a `keys` array of held modifiers on
mouse actions. No API access needed: we build the agent without __init__
and feed SimpleNamespace action objects.
"""
import unittest
from types import SimpleNamespace as NS

from agents.agents.gpt54_computer_use import GPT54ComputerUseAgent
from agents.shared.llm_clients import convert_gpt_key


def _bare_agent():
    return object.__new__(GPT54ComputerUseAgent)


class ConvertGptKeyTests(unittest.TestCase):
    def test_named_keys(self):
        self.assertEqual(convert_gpt_key("ENTER"), "Return")
        self.assertEqual(convert_gpt_key("CTRL"), "ctrl")
        self.assertEqual(convert_gpt_key("SHIFT"), "shift")
        self.assertEqual(convert_gpt_key("META"), "super")
        self.assertEqual(convert_gpt_key("ARROWUP"), "Up")
        self.assertEqual(convert_gpt_key("PAGEDOWN"), "Next")
        self.assertEqual(convert_gpt_key("ESC"), "Escape")
        self.assertEqual(convert_gpt_key("BACKSPACE"), "BackSpace")

    def test_letters_lowercased_for_chords(self):
        self.assertEqual(convert_gpt_key("A"), "a")
        self.assertEqual(convert_gpt_key("a"), "a")

    def test_function_and_unknown_keys(self):
        self.assertEqual(convert_gpt_key("F5"), "F5")
        self.assertEqual(convert_gpt_key("f11"), "F11")
        self.assertEqual(convert_gpt_key("XF86Audio"), "XF86Audio")


class ClickTranslationTests(unittest.TestCase):
    def setUp(self):
        self.agent = _bare_agent()

    def test_click_buttons(self):
        a = NS(type="click", x=10, y=20, button="left", keys=None)
        self.assertEqual(self.agent._convert_single_action(a),
                         [{'mouse': {'left_click': [10, 20]}}])
        a = NS(type="click", x=10, y=20, button="right", keys=None)
        self.assertEqual(self.agent._convert_single_action(a),
                         [{'mouse': {'right_click': [10, 20]}}])
        a = NS(type="click", x=10, y=20, button="middle", keys=None)
        self.assertEqual(self.agent._convert_single_action(a),
                         [{'mouse': {'middle_click': [10, 20]}}])

    def test_shift_click_wraps_with_held_modifiers(self):
        a = NS(type="click", x=5, y=6, button="left", keys=["SHIFT"])
        acts = self.agent._convert_single_action(a)
        self.assertEqual(acts, [
            {'keyboard': {'keys_down': ['shift']}},
            {'mouse': {'left_click': [5, 6]}},
            {'keyboard': {'keys_up': ['shift']}},
        ])

    def test_ctrl_scroll_wraps_with_held_modifiers(self):
        a = NS(type="scroll", x=1, y=2, scrollX=0, scrollY=120, keys=["CTRL"])
        acts = self.agent._convert_single_action(a)
        self.assertEqual(acts[0], {'keyboard': {'keys_down': ['ctrl']}})
        self.assertEqual(acts[-1], {'keyboard': {'keys_up': ['ctrl']}})
        self.assertIn({'mouse': {'scroll': 120}}, acts)


class KeyboardTranslationTests(unittest.TestCase):
    def setUp(self):
        self.agent = _bare_agent()

    def test_keypress_maps_key_names(self):
        a = NS(type="keypress", keys=["CTRL", "A"])
        self.assertEqual(self.agent._convert_single_action(a),
                         [{'keyboard': {'keys': ['ctrl', 'a']}}])

    def test_type_text(self):
        a = NS(type="type", text="hello")
        self.assertEqual(self.agent._convert_single_action(a),
                         [{'keyboard': {'text': 'hello'}}])


class DragTranslationTests(unittest.TestCase):
    def setUp(self):
        self.agent = _bare_agent()

    def test_drag_path(self):
        a = NS(type="drag", path=[NS(x=0, y=0), NS(x=50, y=50), NS(x=99, y=99)],
               keys=None)
        acts = self.agent._convert_single_action(a)
        self.assertEqual(acts[0], {'mouse': {'move': [0, 0]}})
        self.assertEqual(acts[1], {'mouse': {'buttons': {'left_down': True}}})
        self.assertEqual(acts[2], {'mouse': {'move': [50, 50]}})
        self.assertEqual(acts[3], {'mouse': {'move': [99, 99]}})
        self.assertEqual(acts[-1], {'mouse': {'buttons': {'left_up': True}}})


class ActionGroupTests(unittest.TestCase):
    def setUp(self):
        self.agent = _bare_agent()

    def test_batch_splits_into_one_group_per_action(self):
        actions = [
            NS(type="click", x=1, y=1, button="left", keys=None),
            NS(type="keypress", keys=["ENTER"]),
            NS(type="wait", time=1.5),
        ]
        groups = self.agent._build_action_groups(actions, "call_1")
        self.assertEqual(len(groups), 3)
        self.assertEqual(groups[0]['tool_id'], "call_1_0")
        self.assertEqual(groups[2]['actions'],
                         [{'action': 'wait', 'time': 1.5}])

    def test_screenshot_actions_are_dropped_from_batches(self):
        actions = [
            NS(type="screenshot"),
            NS(type="click", x=1, y=1, button="left", keys=None),
        ]
        groups = self.agent._build_action_groups(actions, "call_2")
        self.assertEqual(len(groups), 1)

    def test_screenshot_only_batch_detection(self):
        self.assertTrue(self.agent._is_screenshot_only([NS(type="screenshot")]))
        self.assertFalse(self.agent._is_screenshot_only(
            [NS(type="screenshot"), NS(type="click", x=1, y=1)]))
        self.assertFalse(self.agent._is_screenshot_only([]))


class SerializationTests(unittest.TestCase):
    def test_serialize_click_with_held_keys(self):
        agent = _bare_agent()
        a = NS(type="click", x=7, y=8, button="left", keys=["SHIFT"])
        info = agent._serialize_action(a)
        self.assertEqual(info['type'], 'click')
        self.assertEqual(info['held_keys'], ['SHIFT'])

    def test_serialize_keypress_has_no_held_keys(self):
        agent = _bare_agent()
        info = agent._serialize_action(NS(type="keypress", keys=["CTRL", "C"]))
        self.assertEqual(info['keys'], ["CTRL", "C"])
        self.assertNotIn('held_keys', info)


if __name__ == "__main__":
    unittest.main()
