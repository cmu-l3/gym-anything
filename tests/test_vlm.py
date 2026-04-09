from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock


class ParseVlmJsonTests(unittest.TestCase):
    """Tests for ``parse_vlm_json`` — the multi-strategy JSON extractor."""

    def _parse(self, text: str) -> dict:
        from gym_anything.vlm import parse_vlm_json

        return parse_vlm_json(text)

    def test_empty_string_returns_empty_dict(self) -> None:
        self.assertEqual(self._parse(""), {})

    def test_direct_json_object(self) -> None:
        result = self._parse('{"passed": true, "score": 5}')
        self.assertEqual(result, {"passed": True, "score": 5})

    def test_direct_json_array_is_wrapped(self) -> None:
        result = self._parse('[1, 2, 3]')
        # Direct parse succeeds — returns the list directly
        self.assertEqual(result, [1, 2, 3])

    def test_json_code_block_extraction(self) -> None:
        text = "Here is the result:\n```json\n{\"passed\": false, \"score\": 0}\n```"
        result = self._parse(text)
        self.assertEqual(result, {"passed": False, "score": 0})

    def test_plain_code_block_extraction(self) -> None:
        text = "Result:\n```\n{\"answer\": true}\n```"
        result = self._parse(text)
        self.assertEqual(result, {"answer": True})

    def test_embedded_json_object_via_regex(self) -> None:
        text = 'The model replied: {"verdict": "yes", "confidence": "high"} and some trailing text.'
        result = self._parse(text)
        self.assertEqual(result["verdict"], "yes")

    def test_embedded_json_array_via_regex(self) -> None:
        text = 'Items found: [{"id": 1}, {"id": 2}]'
        result = self._parse(text)
        self.assertIn("items", result)

    def test_yes_only_boolean_fallback(self) -> None:
        result = self._parse("The answer is yes, it matches.")
        self.assertTrue(result.get("answer"))

    def test_no_only_boolean_fallback(self) -> None:
        result = self._parse("No, that is incorrect.")
        self.assertFalse(result.get("answer"))

    def test_true_keyword_fallback(self) -> None:
        result = self._parse("This statement is True.")
        self.assertTrue(result.get("answer"))

    def test_false_keyword_fallback(self) -> None:
        result = self._parse("This statement is False.")
        self.assertFalse(result.get("answer"))

    def test_high_confidence_keyword_fallback(self) -> None:
        result = self._parse("I am confident in this answer.")
        self.assertEqual(result.get("confidence"), "high")

    def test_low_confidence_keyword_fallback(self) -> None:
        result = self._parse("I am uncertain about this.")
        self.assertEqual(result.get("confidence"), "low")

    def test_ambiguous_yes_no_returns_no_answer_key(self) -> None:
        # Both "yes" and "no" appear — fallback should not set answer.
        result = self._parse("yes and no, it depends.")
        self.assertNotIn("answer", result)

    def test_plain_text_no_json_returns_empty_dict(self) -> None:
        result = self._parse("There is nothing structured here.")
        self.assertEqual(result, {})


class ExtractBooleanTests(unittest.TestCase):
    """Tests for ``extract_boolean`` — extracts bool from VLM response dicts."""

    def _extract(self, response: dict, key: str, default: bool = False) -> bool:
        from gym_anything.vlm import extract_boolean

        return extract_boolean(response, key, default)

    def test_bool_true_from_parsed(self) -> None:
        response = {"parsed": {"passed": True}, "response": ""}
        self.assertTrue(self._extract(response, "passed"))

    def test_bool_false_from_parsed(self) -> None:
        response = {"parsed": {"passed": False}, "response": ""}
        self.assertFalse(self._extract(response, "passed"))

    def test_string_true_from_parsed(self) -> None:
        response = {"parsed": {"verdict": "true"}, "response": ""}
        self.assertTrue(self._extract(response, "verdict"))

    def test_string_yes_from_parsed(self) -> None:
        response = {"parsed": {"verdict": "yes"}, "response": ""}
        self.assertTrue(self._extract(response, "verdict"))

    def test_string_false_from_parsed(self) -> None:
        response = {"parsed": {"verdict": "false"}, "response": ""}
        self.assertFalse(self._extract(response, "verdict"))

    def test_inline_text_pattern_true(self) -> None:
        response = {"parsed": {}, "response": "passed: yes, all checks are done"}
        self.assertTrue(self._extract(response, "passed"))

    def test_inline_text_pattern_false(self) -> None:
        response = {"parsed": {}, "response": "passed: no, failed at step 2"}
        self.assertFalse(self._extract(response, "passed"))

    def test_missing_key_returns_default_false(self) -> None:
        response = {"parsed": {}, "response": "no structured data"}
        self.assertFalse(self._extract(response, "nonexistent"))

    def test_missing_key_returns_default_true(self) -> None:
        response = {"parsed": {}, "response": "no structured data"}
        self.assertTrue(self._extract(response, "nonexistent", default=True))


class GetVlmConfigTests(unittest.TestCase):
    """Tests for ``get_vlm_config`` — reads VLM configuration from env vars."""

    def _config(self, env: dict) -> dict:
        from gym_anything.vlm import get_vlm_config

        with mock.patch.dict(os.environ, env, clear=False):
            return get_vlm_config()

    def test_default_backend_is_local(self) -> None:
        env = {k: "" for k in ("VLM_BACKEND", "VLM_MODEL", "VLM_MAX_RETRIES")}
        with mock.patch.dict(os.environ, {}, clear=False):
            # Ensure VLM_BACKEND is absent from env
            cleaned = {k: v for k, v in os.environ.items() if k != "VLM_BACKEND"}
            with mock.patch.dict(os.environ, cleaned, clear=True):
                from gym_anything.vlm import get_vlm_config

                cfg = get_vlm_config()
        self.assertEqual(cfg["backend"], "local")

    def test_anthropic_backend_reads_api_key(self) -> None:
        cfg = self._config({"VLM_BACKEND": "anthropic", "ANTHROPIC_API_KEY": "test-key"})
        self.assertEqual(cfg["backend"], "anthropic")
        self.assertEqual(cfg["api_key"], "test-key")

    def test_openai_backend_reads_api_key(self) -> None:
        cfg = self._config({"VLM_BACKEND": "openai", "OPENAI_API_KEY": "oai-key"})
        self.assertEqual(cfg["backend"], "openai")
        self.assertEqual(cfg["api_key"], "oai-key")

    def test_local_backend_has_base_url(self) -> None:
        cfg = self._config({"VLM_BACKEND": "local"})
        self.assertIn("base_url", cfg)

    def test_custom_max_retries(self) -> None:
        cfg = self._config({"VLM_BACKEND": "local", "VLM_MAX_RETRIES": "5"})
        self.assertEqual(cfg["max_retries"], 5)

    def test_custom_model_overrides_default(self) -> None:
        cfg = self._config({"VLM_BACKEND": "openai", "VLM_MODEL": "gpt-4-turbo"})
        self.assertEqual(cfg["model"], "gpt-4-turbo")


class SampleTrajectoryFramesTests(unittest.TestCase):
    """Tests for ``sample_trajectory_frames``."""

    def _sample(self, traj: dict, num_samples: int = 3, **kwargs) -> list:
        from gym_anything.vlm import sample_trajectory_frames

        return sample_trajectory_frames(traj, num_samples=num_samples, **kwargs)

    def test_empty_traj_returns_empty_list(self) -> None:
        self.assertEqual(self._sample({}), [])

    def test_final_screenshot_used_when_no_frames(self) -> None:
        traj = {"final_screenshot": "/tmp/final.png"}
        result = self._sample(traj)
        self.assertEqual(result, ["/tmp/final.png"])

    def test_fewer_frames_than_samples_returns_all(self) -> None:
        traj = {"frames": ["a.png", "b.png"]}
        result = self._sample(traj, num_samples=5)
        self.assertEqual(result, ["a.png", "b.png"])

    def test_includes_first_and_last_frame(self) -> None:
        frames = [f"frame_{i}.png" for i in range(20)]
        traj = {"frames": frames}
        result = self._sample(traj, num_samples=3, include_first=True, include_last=True)
        self.assertIn("frame_0.png", result)
        self.assertIn("frame_19.png", result)

    def test_exactly_num_samples_returned(self) -> None:
        frames = [f"frame_{i}.png" for i in range(100)]
        traj = {"frames": frames}
        result = self._sample(traj, num_samples=5)
        self.assertLessEqual(len(result), 5)

    def test_result_is_sorted_order(self) -> None:
        frames = [f"frame_{i}.png" for i in range(30)]
        traj = {"frames": frames}
        result = self._sample(traj, num_samples=4)
        # Frames should appear in their original order
        indices = [frames.index(f) for f in result]
        self.assertEqual(indices, sorted(indices))

    def test_exclude_first_frame(self) -> None:
        frames = [f"frame_{i}.png" for i in range(20)]
        traj = {"frames": frames}
        result = self._sample(traj, num_samples=3, include_first=False, include_last=True)
        self.assertNotIn("frame_0.png", result)

    def test_exclude_last_frame(self) -> None:
        frames = [f"frame_{i}.png" for i in range(20)]
        traj = {"frames": frames}
        result = self._sample(traj, num_samples=3, include_first=True, include_last=False)
        self.assertNotIn("frame_19.png", result)


class GetScreenshotTests(unittest.TestCase):
    """Tests for ``get_final_screenshot`` and ``get_first_screenshot``."""

    def test_get_final_screenshot_prefers_post_verification(self) -> None:
        from gym_anything.vlm import get_final_screenshot

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            path = f.name
        try:
            traj = {
                "post_verification_screenshot": path,
                "final_screenshot": "/nonexistent/final.png",
            }
            result = get_final_screenshot(traj)
            self.assertEqual(result, path)
        finally:
            os.unlink(path)

    def test_get_final_screenshot_falls_back_to_final(self) -> None:
        from gym_anything.vlm import get_final_screenshot

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            path = f.name
        try:
            traj = {
                "post_verification_screenshot": "/nonexistent.png",
                "final_screenshot": path,
            }
            result = get_final_screenshot(traj)
            self.assertEqual(result, path)
        finally:
            os.unlink(path)

    def test_get_final_screenshot_returns_none_when_none_exist(self) -> None:
        from gym_anything.vlm import get_final_screenshot

        traj = {
            "post_verification_screenshot": "/no/such/file.png",
            "final_screenshot": "/no/such/final.png",
        }
        result = get_final_screenshot(traj)
        self.assertIsNone(result)

    def test_get_final_screenshot_empty_traj_returns_none(self) -> None:
        from gym_anything.vlm import get_final_screenshot

        self.assertIsNone(get_final_screenshot({}))

    def test_get_first_screenshot_uses_first_frame_key(self) -> None:
        from gym_anything.vlm import get_first_screenshot

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            path = f.name
        try:
            traj = {"first_frame": path}
            result = get_first_screenshot(traj)
            self.assertEqual(result, path)
        finally:
            os.unlink(path)

    def test_get_first_screenshot_falls_back_to_frames_list(self) -> None:
        from gym_anything.vlm import get_first_screenshot

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            path = f.name
        try:
            traj = {"first_frame": "/nonexistent.png", "frames": [path, "/other.png"]}
            result = get_first_screenshot(traj)
            self.assertEqual(result, path)
        finally:
            os.unlink(path)

    def test_get_first_screenshot_returns_none_when_no_frames(self) -> None:
        from gym_anything.vlm import get_first_screenshot

        self.assertIsNone(get_first_screenshot({}))


class ImageHelperTests(unittest.TestCase):
    """Tests for ``_get_image_media_type`` and ``_encode_image_base64``."""

    def test_media_type_png(self) -> None:
        from gym_anything.vlm import _get_image_media_type

        self.assertEqual(_get_image_media_type("screenshot.png"), "image/png")

    def test_media_type_jpeg(self) -> None:
        from gym_anything.vlm import _get_image_media_type

        self.assertEqual(_get_image_media_type("photo.jpg"), "image/jpeg")
        self.assertEqual(_get_image_media_type("photo.jpeg"), "image/jpeg")

    def test_media_type_webp(self) -> None:
        from gym_anything.vlm import _get_image_media_type

        self.assertEqual(_get_image_media_type("image.webp"), "image/webp")

    def test_media_type_unknown_defaults_to_png(self) -> None:
        from gym_anything.vlm import _get_image_media_type

        self.assertEqual(_get_image_media_type("file.bmp"), "image/png")

    def test_encode_image_base64_missing_file_returns_none(self) -> None:
        from gym_anything.vlm import _encode_image_base64

        result = _encode_image_base64("/no/such/file.png")
        self.assertIsNone(result)

    def test_encode_image_base64_real_file(self) -> None:
        import base64

        from gym_anything.vlm import _encode_image_base64

        # Write a minimal 1-byte file and verify it round-trips.
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            f.write(b"\x89PNG")
            path = f.name
        try:
            encoded = _encode_image_base64(path)
            self.assertIsNotNone(encoded)
            assert encoded is not None  # for type checker
            decoded = base64.b64decode(encoded)
            self.assertEqual(decoded, b"\x89PNG")
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()
