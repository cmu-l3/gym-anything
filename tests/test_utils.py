from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from gym_anything.utils.jsonl import JSONLWriter
from gym_anything.utils.merge import _merge_lists_by_key, deep_merge_env_dict
from gym_anything.utils.yaml import load_structured_file


class TestJSONLWriter(unittest.TestCase):
    def test_write_single_record(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "out.jsonl"
            writer = JSONLWriter(path)
            writer.write({"key": "value"})
            writer.close()
            lines = path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 1)
            self.assertEqual(json.loads(lines[0]), {"key": "value"})

    def test_write_multiple_records(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "out.jsonl"
            writer = JSONLWriter(path)
            records = [{"id": 1, "val": "a"}, {"id": 2, "val": "b"}, {"id": 3, "val": "c"}]
            for r in records:
                writer.write(r)
            writer.close()
            lines = path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 3)
            for i, line in enumerate(lines):
                self.assertEqual(json.loads(line), records[i])

    def test_write_creates_parent_dirs(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "nested" / "dir" / "out.jsonl"
            writer = JSONLWriter(path)
            writer.write({"x": 1})
            writer.close()
            self.assertTrue(path.exists())

    def test_write_appends_to_existing_file(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "out.jsonl"
            # First writer
            w1 = JSONLWriter(path)
            w1.write({"batch": 1})
            w1.close()
            # Second writer opens in append mode
            w2 = JSONLWriter(path)
            w2.write({"batch": 2})
            w2.close()
            lines = path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 2)
            self.assertEqual(json.loads(lines[0])["batch"], 1)
            self.assertEqual(json.loads(lines[1])["batch"], 2)

    def test_write_records_end_with_newline(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "out.jsonl"
            writer = JSONLWriter(path)
            writer.write({"a": 1})
            writer.close()
            raw = path.read_text(encoding="utf-8")
            self.assertTrue(raw.endswith("\n"))

    def test_write_various_types(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "out.jsonl"
            writer = JSONLWriter(path)
            writer.write({"int": 42, "float": 3.14, "bool": True, "null": None, "list": [1, 2]})
            writer.close()
            lines = path.read_text(encoding="utf-8").splitlines()
            obj = json.loads(lines[0])
            self.assertEqual(obj["int"], 42)
            self.assertAlmostEqual(obj["float"], 3.14)
            self.assertTrue(obj["bool"])
            self.assertIsNone(obj["null"])
            self.assertEqual(obj["list"], [1, 2])

    def test_close_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "out.jsonl"
            writer = JSONLWriter(path)
            writer.write({"x": 1})
            writer.close()
            # Second close must not raise
            writer.close()


class TestMergeListsByKey(unittest.TestCase):
    def test_appends_new_items(self):
        base = [{"type": "a", "val": 1}]
        add = [{"type": "b", "val": 2}]
        result = _merge_lists_by_key(base, add, key="type")
        self.assertEqual(len(result), 2)
        self.assertEqual(result[1], {"type": "b", "val": 2})

    def test_merges_existing_items_by_key(self):
        base = [{"type": "a", "val": 1, "extra": "keep"}]
        add = [{"type": "a", "val": 99}]
        result = _merge_lists_by_key(base, add, key="type")
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["val"], 99)
        self.assertEqual(result[0]["extra"], "keep")

    def test_does_not_mutate_base(self):
        base = [{"type": "a", "val": 1}]
        add = [{"type": "a", "val": 2}]
        _merge_lists_by_key(base, add, key="type")
        self.assertEqual(base[0]["val"], 1)

    def test_non_dict_items_are_appended(self):
        base = [{"type": "a"}]
        add = ["string_item", 42]
        result = _merge_lists_by_key(base, add, key="type")
        self.assertIn("string_item", result)
        self.assertIn(42, result)

    def test_empty_base(self):
        add = [{"type": "x", "v": 1}]
        result = _merge_lists_by_key([], add, key="type")
        self.assertEqual(result, [{"type": "x", "v": 1}])

    def test_empty_add(self):
        base = [{"type": "x", "v": 1}]
        result = _merge_lists_by_key(base, [], key="type")
        self.assertEqual(result, base)

    def test_multiple_items_merge_correct_one(self):
        base = [{"type": "a", "v": 1}, {"type": "b", "v": 2}]
        add = [{"type": "b", "v": 99}]
        result = _merge_lists_by_key(base, add, key="type")
        self.assertEqual(result[0]["v"], 1)
        self.assertEqual(result[1]["v"], 99)


class TestDeepMergeEnvDict(unittest.TestCase):
    def test_scalar_override(self):
        base = {"a": 1, "b": 2}
        override = {"b": 99}
        result = deep_merge_env_dict(base, override)
        self.assertEqual(result["a"], 1)
        self.assertEqual(result["b"], 99)

    def test_nested_dict_merged_recursively(self):
        base = {"nested": {"x": 1, "y": 2}}
        override = {"nested": {"y": 99, "z": 3}}
        result = deep_merge_env_dict(base, override)
        self.assertEqual(result["nested"]["x"], 1)
        self.assertEqual(result["nested"]["y"], 99)
        self.assertEqual(result["nested"]["z"], 3)

    def test_observation_list_merged_by_type(self):
        base = {"observation": [{"type": "rgb_screen", "fps": 10}]}
        override = {"observation": [{"type": "rgb_screen", "fps": 30}]}
        result = deep_merge_env_dict(base, override)
        self.assertEqual(len(result["observation"]), 1)
        self.assertEqual(result["observation"][0]["fps"], 30)

    def test_action_list_merged_by_type(self):
        base = {"action": [{"type": "mouse", "events": ["click"]}]}
        override = {"action": [{"type": "mouse", "events": ["click", "move"]}]}
        result = deep_merge_env_dict(base, override)
        self.assertEqual(len(result["action"]), 1)
        self.assertEqual(result["action"][0]["events"], ["click", "move"])

    def test_observation_list_new_type_appended(self):
        base = {"observation": [{"type": "rgb_screen"}]}
        override = {"observation": [{"type": "ui_tree"}]}
        result = deep_merge_env_dict(base, override)
        self.assertEqual(len(result["observation"]), 2)

    def test_non_observation_action_lists_concatenated(self):
        base = {"tags": ["a", "b"]}
        override = {"tags": ["c"]}
        result = deep_merge_env_dict(base, override)
        # Non-observation/action lists: override wins (replace)
        self.assertEqual(result["tags"], ["c"])

    def test_does_not_mutate_base(self):
        base = {"a": 1, "nested": {"x": 1}}
        override = {"a": 2, "nested": {"x": 99}}
        deep_merge_env_dict(base, override)
        self.assertEqual(base["a"], 1)
        self.assertEqual(base["nested"]["x"], 1)

    def test_new_keys_added(self):
        base = {"a": 1}
        override = {"b": 2}
        result = deep_merge_env_dict(base, override)
        self.assertEqual(result["a"], 1)
        self.assertEqual(result["b"], 2)

    def test_empty_override(self):
        base = {"a": 1, "b": 2}
        result = deep_merge_env_dict(base, {})
        self.assertEqual(result, base)

    def test_empty_base(self):
        override = {"a": 1}
        result = deep_merge_env_dict({}, override)
        self.assertEqual(result["a"], 1)


class TestLoadStructuredFile(unittest.TestCase):
    def test_load_json(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "data.json"
            path.write_text(json.dumps({"key": "value", "num": 42}), encoding="utf-8")
            result = load_structured_file(path)
            self.assertEqual(result["key"], "value")
            self.assertEqual(result["num"], 42)

    def test_load_yaml(self):
        pytest = __import__("importlib").util.find_spec("yaml")
        if pytest is None:
            self.skipTest("PyYAML not installed")
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "data.yaml"
            path.write_text("key: value\nnum: 42\n", encoding="utf-8")
            result = load_structured_file(path)
            self.assertEqual(result["key"], "value")
            self.assertEqual(result["num"], 42)

    def test_load_yml_extension(self):
        pytest = __import__("importlib").util.find_spec("yaml")
        if pytest is None:
            self.skipTest("PyYAML not installed")
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "data.yml"
            path.write_text("x: 1\n", encoding="utf-8")
            result = load_structured_file(path)
            self.assertEqual(result["x"], 1)

    def test_unsupported_extension_raises(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "data.toml"
            path.write_text("x = 1\n", encoding="utf-8")
            with self.assertRaises(ValueError) as ctx:
                load_structured_file(path)
            self.assertIn("Unsupported file type", str(ctx.exception))

    def test_yaml_non_dict_raises(self):
        pytest = __import__("importlib").util.find_spec("yaml")
        if pytest is None:
            self.skipTest("PyYAML not installed")
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "data.yaml"
            path.write_text("- item1\n- item2\n", encoding="utf-8")
            with self.assertRaises(ValueError) as ctx:
                load_structured_file(path)
            self.assertIn("mapping", str(ctx.exception))

    def test_json_nested(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "nested.json"
            data = {"outer": {"inner": [1, 2, 3]}}
            path.write_text(json.dumps(data), encoding="utf-8")
            result = load_structured_file(path)
            self.assertEqual(result["outer"]["inner"], [1, 2, 3])


if __name__ == "__main__":
    unittest.main()
