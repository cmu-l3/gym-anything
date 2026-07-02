import inspect
import json
import tempfile
import unittest
from pathlib import Path

from benchmarks.cua_world.hub import build_task_rows
from gym_anything.api import from_config
from gym_anything.integrations.computer_tool import (
    PARSE_ERROR,
    WRONG_TOOL,
    make_computer_tool,
    parse_tool_calls,
    prune_screenshots,
    to_pixels,
    translate_action,
)

try:
    import verifiers  # noqa: F401

    HAS_VERIFIERS = True
except ImportError:
    HAS_VERIFIERS = False

RES = (1920, 1080)


class ComputerToolTranslationTests(unittest.TestCase):
    def test_norm1000_click_scales_to_pixels(self) -> None:
        plan = translate_action({"action": "left_click", "coordinate": [500, 500]}, RES, "norm1000")
        self.assertIsNone(plan["error"])
        self.assertEqual(plan["actions"], [{"mouse": {"left_click": [960, 540]}}])

    def test_pixel_mode_passes_coordinates_through(self) -> None:
        self.assertEqual(to_pixels([100, 200], RES, "pixel"), (100, 200))

    def test_mouse_move_maps_to_move_action(self) -> None:
        plan = translate_action({"action": "mouse_move", "coordinate": [0, 1000]}, RES, "norm1000")
        self.assertEqual(plan["actions"], [{"mouse": {"move": [0, 1080]}}])

    def test_drag_uses_both_coordinates(self) -> None:
        plan = translate_action(
            {"action": "left_click_drag", "coordinate": [0, 0], "coordinate2": [1000, 1000]},
            RES,
            "norm1000",
        )
        self.assertEqual(plan["actions"], [{"mouse": {"left_click_drag": [[0, 0], [1920, 1080]]}}])

    def test_scroll_with_coordinate_moves_first(self) -> None:
        plan = translate_action({"action": "scroll", "pixels": -300, "coordinate": [500, 500]}, RES, "norm1000")
        self.assertEqual(
            plan["actions"],
            [{"mouse": {"move": [960, 540]}}, {"mouse": {"scroll": -300}}],
        )

    def test_key_accepts_plus_joined_string(self) -> None:
        plan = translate_action({"action": "key", "keys": "ctrl+s"}, RES, "norm1000")
        self.assertEqual(plan["actions"], [{"keyboard": {"keys": ["ctrl", "s"]}}])

    def test_type_produces_keyboard_text(self) -> None:
        plan = translate_action({"action": "type", "text": "hello"}, RES, "norm1000")
        self.assertEqual(plan["actions"], [{"keyboard": {"text": "hello"}}])

    def test_wait_sets_wait_without_actions(self) -> None:
        plan = translate_action({"action": "wait", "time": 2.5}, RES, "norm1000")
        self.assertEqual(plan["wait"], 2.5)
        self.assertEqual(plan["actions"], [])

    def test_screenshot_is_a_noop(self) -> None:
        plan = translate_action({"action": "screenshot"}, RES, "norm1000")
        self.assertEqual(plan["actions"], [])
        self.assertIsNone(plan["error"])
        self.assertFalse(plan["terminal"])

    def test_terminate_marks_terminal(self) -> None:
        plan = translate_action({"action": "terminate", "status": "success"}, RES, "norm1000")
        self.assertTrue(plan["terminal"])

    def test_unknown_action_reports_error(self) -> None:
        plan = translate_action({"action": "levitate"}, RES, "norm1000")
        self.assertIn("Unknown action", plan["error"])

    def test_missing_coordinate_reports_error(self) -> None:
        plan = translate_action({"action": "left_click"}, RES, "norm1000")
        self.assertIn("Malformed arguments", plan["error"])

    def test_tool_schema_lists_all_actions(self) -> None:
        tool = make_computer_tool("norm1000")
        self.assertEqual(tool["name"], "computer")
        self.assertIn("terminate", tool["parameters"]["properties"]["action"]["enum"])


class ParseToolCallsTests(unittest.TestCase):
    def test_parses_dict_style_tool_call(self) -> None:
        message = {
            "tool_calls": [
                {"id": "c1", "function": {"name": "computer", "arguments": '{"action": "screenshot"}'}}
            ]
        }
        self.assertEqual(parse_tool_calls(message), [("c1", {"action": "screenshot"})])

    def test_flags_calls_to_other_tools(self) -> None:
        message = {"tool_calls": [{"id": "c1", "function": {"name": "bash", "arguments": "{}"}}]}
        (tc_id, args), = parse_tool_calls(message)
        self.assertEqual(args["action"], WRONG_TOOL)

    def test_flags_unparseable_arguments(self) -> None:
        message = {"tool_calls": [{"id": "c1", "function": {"name": "computer", "arguments": "{nope"}}]}
        (tc_id, args), = parse_tool_calls(message)
        self.assertEqual(args["action"], PARSE_ERROR)

    def test_message_without_tool_calls_yields_nothing(self) -> None:
        self.assertEqual(parse_tool_calls({"role": "assistant", "content": "hi"}), [])


def _image_message(tag: str) -> dict:
    return {
        "role": "user",
        "content": [
            {"type": "text", "text": tag},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{tag}"}},
        ],
    }


class PruneScreenshotsTests(unittest.TestCase):
    def test_keeps_only_most_recent_images(self) -> None:
        messages = [_image_message("a"), {"role": "assistant", "content": "ok"}, _image_message("b"), _image_message("c")]
        pruned = prune_screenshots(messages, keep_recent=1)
        self.assertNotIn("image_url", json.dumps(pruned[0]))
        self.assertIn("[older screenshot removed]", json.dumps(pruned[0]))
        self.assertNotIn("image_url", json.dumps(pruned[2]))
        self.assertIn("image_url", json.dumps(pruned[3]))

    def test_zero_drops_all_images(self) -> None:
        pruned = prune_screenshots([_image_message("a")], keep_recent=0)
        self.assertNotIn("image_url", json.dumps(pruned))

    def test_negative_means_unlimited(self) -> None:
        messages = [_image_message("a"), _image_message("b")]
        self.assertEqual(prune_screenshots(messages, keep_recent=-1), messages)


class HubRowsTests(unittest.TestCase):
    def test_rows_carry_absolute_env_dir_and_prompt(self) -> None:
        rows = build_task_rows("gimp_env", max_examples=3)
        self.assertTrue(rows)
        for row in rows:
            self.assertTrue(Path(row["info"]["env_dir"]).is_absolute())
            self.assertEqual(row["info"]["env_name"], "gimp_env")
            self.assertTrue(row["prompt"][0]["content"])
            self.assertTrue(row["task"].startswith("gimp_env/"))

    def test_task_id_whitelist_filters(self) -> None:
        all_rows = build_task_rows("gimp_env")
        wanted = all_rows[0]["info"]["task_id"]
        rows = build_task_rows("gimp_env", task_ids=[wanted])
        self.assertEqual([r["info"]["task_id"] for r in rows], [wanted])

    def test_no_matches_raises(self) -> None:
        with self.assertRaises(ValueError):
            build_task_rows("gimp_env", task_ids=["definitely-not-a-task"])


class FromConfigOverridesTests(unittest.TestCase):
    def test_from_config_accepts_overrides(self) -> None:
        self.assertIn("overrides", inspect.signature(from_config).parameters)

    def test_overrides_reach_env_spec(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "env.json").write_text(
                json.dumps(
                    {
                        "id": "demo-env",
                        "observation": [{"type": "rgb_screen"}],
                        "action": [{"type": "mouse"}],
                    }
                ),
                encoding="utf-8",
            )
            env = from_config(root, overrides={"runner": "local"})
            try:
                self.assertEqual(env.env_spec.runner, "local")
            finally:
                env.close()

    def test_relative_mounts_resolve_against_env_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "scripts").mkdir()
            (root / "env.json").write_text(
                json.dumps(
                    {
                        "id": "demo-env",
                        "observation": [{"type": "rgb_screen"}],
                        "action": [{"type": "mouse"}],
                        "runner": "local",
                        "mounts": [
                            {"target": "/workspace/scripts", "source": "scripts", "mode": "ro"},
                            {"target": "/workspace/missing", "source": "does/not/exist", "mode": "ro"},
                        ],
                    }
                ),
                encoding="utf-8",
            )
            env = from_config(root)
            try:
                sources = {m.target: m.source for m in env.env_spec.mounts}
                self.assertEqual(sources["/workspace/scripts"], str((root / "scripts").resolve()))
                # Unresolvable sources stay as written so runners report them.
                self.assertEqual(sources["/workspace/missing"], "does/not/exist")
            finally:
                env.close()


@unittest.skipUnless(HAS_VERIFIERS, "verifiers not installed")
class VerifiersAdapterTests(unittest.TestCase):
    def test_finalize_runs_verifier_once_while_env_alive(self) -> None:
        from gym_anything.integrations.verifiers import _finalize_episode

        class FakeEnv:
            def __init__(self) -> None:
                self.mark_done_calls = 0

            def step(self, actions, mark_done=False):
                assert mark_done
                self.mark_done_calls += 1
                return {}, 1.0, True, {"verifier": {"passed": True, "score": 100}}

        fake = FakeEnv()
        state = {"ga_env": fake}
        _finalize_episode(state)
        self.assertEqual(state["episode_reward"], 1.0)
        self.assertTrue(state["verifier"]["passed"])
        # Idempotent: the terminate path and the cleanup handler may both run.
        _finalize_episode(state)
        self.assertEqual(fake.mark_done_calls, 1)

    def test_finalize_without_env_surfaces_boot_failure(self) -> None:
        from gym_anything.integrations.verifiers import _finalize_episode

        state = {}
        _finalize_episode(state)
        self.assertEqual(state["episode_reward"], 0.0)
        self.assertIn("error", state["verifier"])

    def test_build_computer_env_constructs_environment(self) -> None:
        import verifiers as vf

        from gym_anything.integrations.verifiers import build_computer_env

        rows = [
            {
                "prompt": [{"role": "user", "content": "do the thing"}],
                "info": {"env_dir": "/nonexistent", "env_name": "e", "task_id": "t", "seed": 0},
                "task": "e/t",
            }
        ]
        env = build_computer_env(rows, runner=None, env_id="test-env")
        self.assertIsInstance(env, vf.Environment)


if __name__ == "__main__":
    unittest.main()
