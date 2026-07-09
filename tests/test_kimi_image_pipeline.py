from __future__ import annotations

import base64
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from PIL import Image

from agents.agents.kimi import KimiAzureAgent
from agents.agents.kimi_distill import KimiDistillAgent
from agents.agents.qwen35_dsl import Qwen35DSLAgent
from agents.agents.qwen35_real import Qwen35RealAgent
from agents.agents.qwen35vl import (
    Qwen35VLAgent,
    _normalize_keyboard_action_keys,
    _parse_modifier_keys,
)


class AgentImagePipelineTests(unittest.TestCase):
    def _make_agent(self, agent_cls, save_dir, **agent_args):
        def setup_custom_logger(agent):
            agent.save_folder_custom = str(save_dir)

        with mock.patch.object(agent_cls, "setup_custom_logger", setup_custom_logger):
            return agent_cls(agent_args=agent_args)

    def test_kimi_process_image_uses_jpeg_payload_and_async_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            save_dir = Path(tmp)
            agent = self._make_agent(
                KimiAzureAgent,
                save_dir,
                image_format="jpeg",
                jpeg_quality=85,
                async_image_save=True,
            )
            agent.step_idx = 3
            agent.task_description = "inspect the screen"

            image = Image.new("RGB", (64, 48), (20, 120, 220))
            image_b64, image_path = agent.process_image({"image": image})
            image_bytes = base64.b64decode(image_b64)

            self.assertEqual(Path(image_path).suffix, ".jpg")
            self.assertTrue(image_bytes.startswith(b"\xff\xd8"))
            self.assertIn(
                "data:image/jpeg;base64,",
                agent.build_messages(image_b64)[1]["content"][0]["image_url"]["url"],
            )

            agent._wait_for_image_saves()
            self.assertEqual(Path(image_path).read_bytes(), image_bytes)

    def test_kimi_distill_initializes_inherited_image_pipeline(self):
        with tempfile.TemporaryDirectory() as tmp:
            agent = self._make_agent(KimiDistillAgent, Path(tmp), image_format="jpeg")
            self.assertEqual(agent.image_format, "jpeg")
            self.assertEqual(agent.image_mime_type, "image/jpeg")
            agent._wait_for_image_saves()

    def test_prime_rgb_image_payload_uses_raw_data_url_and_jpeg_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            save_dir = Path(tmp)
            agent = self._make_agent(
                Qwen35RealAgent,
                save_dir,
                image_format="prime_rgb",
                prime_rgb_width=96,
                prime_rgb_height=54,
            )
            agent.step_idx = 0

            image_b64, image_path = agent.process_image(
                {"image": Image.new("RGB", (192, 108), (20, 120, 220))}
            )
            image_bytes = base64.b64decode(image_b64)

            self.assertEqual(len(image_bytes), 96 * 54 * 3)
            self.assertEqual(agent._processed_size(image_b64), (96, 54))
            self.assertTrue(agent._image_data_url(image_b64).startswith(
                "data:application/x.prime-rgb;w=96;h=54;base64,"
            ))
            agent._wait_for_image_saves()
            self.assertEqual(Path(image_path).suffix, ".jpg")
            self.assertTrue(Path(image_path).read_bytes().startswith(b"\xff\xd8"))

    def test_qwen35_uses_fast_observation_image_and_jpeg_pipeline(self):
        response = """Action: Finish.
<tool_call>
<function=computer_use>
<parameter=action>terminate</parameter>
<parameter=status>success</parameter>
</function>
</tool_call>"""

        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.object(Qwen35VLAgent, "llm_call", staticmethod(lambda *a, **k: response)):
            save_dir = Path(tmp)
            agent = self._make_agent(
                Qwen35VLAgent,
                save_dir,
                image_format="jpeg",
                jpeg_quality=85,
                async_image_save=True,
            )
            agent.init(
                task_description="finish the task",
                display_resolution=(1920, 1080),
                save_path=str(save_dir),
            )

            actions = agent.step(
                {"screen": {"image": Image.new("RGB", (64, 48), (20, 120, 220))}},
                [],
            )
            image_path = next(iter(agent.b64_to_path.values()))
            agent._wait_for_image_saves()

            self.assertTrue(actions[0]["metadata"]["is_terminal"])
            self.assertEqual(Path(image_path).suffix, ".jpg")
            self.assertTrue(Path(image_path).read_bytes().startswith(b"\xff\xd8"))
            self.assertIn("process_observation_ms", agent.last_step_timing)

    def test_qwen35_can_reference_cached_history_images_by_uuid(self):
        with tempfile.TemporaryDirectory() as tmp:
            save_dir = Path(tmp)
            agent = self._make_agent(
                Qwen35VLAgent,
                save_dir,
                image_format="jpeg",
                image_cache_uuids=True,
                image_cache_uuid_prefix="test-run",
            )
            agent.init(
                task_description="inspect the screen",
                display_resolution=(1920, 1080),
                save_path=str(save_dir),
            )

            agent.step_idx = 0
            first_b64, _first_path = agent.process_image(
                {"image": Image.new("RGB", (64, 48), (20, 120, 220))}
            )
            agent._remember_screenshot(first_b64)
            agent.responses.append("Action: previous")
            agent.history.append("previous action")

            agent.step_idx = 1
            second_b64, second_path = agent.process_image(
                {"image": Image.new("RGB", (64, 48), (20, 120, 220))}
            )
            agent._remember_screenshot(second_b64)
            agent.b64_to_path[first_b64] = str(save_dir / "observation_0.jpg")
            agent.b64_to_path[second_b64] = second_path

            messages = agent.build_messages(second_b64)
            history_image = messages[1]["content"][0]
            current_image = messages[3]["content"][0]

            self.assertEqual(history_image["uuid"], "test-run-frame-000000")
            self.assertIsNone(history_image["image_url"])
            self.assertEqual(current_image["uuid"], "test-run-frame-000001")
            self.assertIn("data:image/jpeg;base64,", current_image["image_url"]["url"])

            agent.save_messages(messages)
            saved = (save_dir / "messages_step_1.json").read_text()
            self.assertNotIn("base64,", saved)
            self.assertIn('"cached": true', saved)
            agent._wait_for_image_saves()

    def test_qwen35_real_long_history_uses_per_frame_uuid_cache_references(self):
        with tempfile.TemporaryDirectory() as tmp:
            save_dir = Path(tmp)
            agent = self._make_agent(
                Qwen35RealAgent,
                save_dir,
                image_format="jpeg",
                image_cache_uuids=True,
                image_cache_uuid_prefix="test-run",
                image_max=100,
            )
            agent.init(
                task_description="inspect the screen",
                display_resolution=(1920, 1080),
                save_path=str(save_dir),
            )

            for step_idx in range(2):
                agent.step_idx = step_idx
                image_b64, image_path = agent.process_image(
                    {"image": Image.new("RGB", (64, 48), (20, 120, 220))}
                )
                agent._remember_screenshot(image_b64)
                agent.b64_to_path[image_b64] = image_path
                if step_idx == 0:
                    agent.responses.append("Action: previous")
                    agent.history.append("previous action")

            messages = agent.build_messages(64, 48)
            history_image = messages[1]["content"][0]
            current_image = messages[3]["content"][1]

            self.assertEqual(history_image["uuid"], "test-run-frame-000000")
            self.assertIsNone(history_image["image_url"])
            self.assertEqual(current_image["uuid"], "test-run-frame-000001")
            self.assertIn("data:image/jpeg;base64,", current_image["image_url"]["url"])

            agent.save_messages(messages)
            saved = (save_dir / "messages_step_1.json").read_text()
            self.assertNotIn("base64,", saved)
            self.assertIn('"cached": true', saved)
            agent._wait_for_image_saves()

    def test_qwen35_dsl_incremental_messages_send_only_delta_after_first_turn(self):
        with tempfile.TemporaryDirectory() as tmp:
            save_dir = Path(tmp)
            agent = self._make_agent(
                Qwen35DSLAgent,
                save_dir,
                image_format="jpeg",
                image_cache_uuids=True,
                image_cache_uuid_prefix="dsl-run",
            )
            agent.init(
                task_description="inspect the screen",
                display_resolution=(1920, 1080),
                save_path=str(save_dir),
            )

            agent.step_idx = 0
            first_b64, first_path = agent.process_image(
                {"image": Image.new("RGB", (64, 48), (20, 120, 220))}
            )
            agent._remember_screenshot(first_b64)
            agent.b64_to_path[first_b64] = first_path
            first_turn = agent.build_incremental_messages(64, 48)

            agent.responses.append(">> click 10,20")
            agent.step_idx = 1
            second_b64, second_path = agent.process_image(
                {"image": Image.new("RGB", (64, 48), (20, 120, 220))}
            )
            agent._remember_screenshot(second_b64)
            agent.b64_to_path[second_b64] = second_path
            delta = agent.build_incremental_messages(64, 48)

            self.assertTrue(agent.incremental_messages)
            self.assertEqual(first_turn[0]["role"], "system")
            self.assertEqual(delta[0]["role"], "assistant")
            self.assertEqual(delta[0]["content"][0]["text"], ">> click 10,20")
            self.assertEqual(delta[1]["role"], "user")
            images = [
                part
                for part in delta[1]["content"]
                if part.get("type") == "image_url"
            ]
            self.assertEqual(len(images), 1)
            self.assertEqual(images[0]["uuid"], "dsl-run-frame-000001")
            self.assertIn("base64,", images[0]["image_url"]["url"])
            agent._wait_for_image_saves()

    def test_image_cache_uuid_prefix_is_unique_per_agent_run_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            first = self._make_agent(
                Qwen35VLAgent,
                Path(tmp) / "first",
                image_format="jpeg",
                image_cache_uuids=True,
            )
            second = self._make_agent(
                Qwen35VLAgent,
                Path(tmp) / "second",
                image_format="jpeg",
                image_cache_uuids=True,
            )

            first.step_idx = 0
            second.step_idx = 0
            first_b64, _ = first.process_image({"image": Image.new("RGB", (64, 48), (20, 120, 220))})
            second_b64, _ = second.process_image({"image": Image.new("RGB", (64, 48), (20, 120, 220))})

            self.assertNotEqual(first.b64_to_uuid[first_b64], second.b64_to_uuid[second_b64])
            self.assertTrue(first.b64_to_uuid[first_b64].endswith("-frame-000000"))
            self.assertTrue(second.b64_to_uuid[second_b64].endswith("-frame-000000"))
            first._wait_for_image_saves()
            second._wait_for_image_saves()

    def test_qwen35_modifier_keys_normalize_list_like_text(self):
        self.assertEqual(_parse_modifier_keys("['ctrl']"), ["ctrl"])
        self.assertEqual(_parse_modifier_keys("['ctrl"), ["ctrl"])
        self.assertEqual(_parse_modifier_keys('["ctrl", "shift"]'), ["ctrl", "shift"])
        self.assertEqual(_parse_modifier_keys("control+shift"), ["ctrl", "shift"])
        self.assertEqual(_parse_modifier_keys(["ctrl', 'k"]), ["ctrl", "k"])

    def test_qwen35_normalizes_keyboard_keys_at_dispatch_boundary(self):
        actions = _normalize_keyboard_action_keys(
            [{"keyboard": {"keys": ["['ctrl"], "text": ""}}]
        )
        self.assertEqual(actions[0]["keyboard"]["keys"], ["ctrl"])

    def test_qwen35_missing_required_key_payload_becomes_parse_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            agent = self._make_agent(Qwen35VLAgent, Path(tmp), image_format="jpeg")
            response = """Action: Press shortcut.
<tool_call>
<function=computer_use>
<parameter=action>key</parameter>
</function>
</tool_call>"""

            parsed = agent._parse_response(response)

            self.assertEqual(parsed["actions"], [{"action": "screenshot"}])
            self.assertTrue(parsed["metadata"]["parse_error"])
            agent._wait_for_image_saves()


if __name__ == "__main__":
    unittest.main()
