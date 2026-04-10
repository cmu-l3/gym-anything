from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from gym_anything.verification.imports import (
    build_verifier_import_paths,
    discover_local_modules,
    find_missing_imports,
    list_defined_functions,
    list_import_roots,
    verifier_import_context,
)


class BuildVerifierImportPathsTests(unittest.TestCase):
    """Tests for build_verifier_import_paths."""

    def test_returns_empty_when_both_none(self) -> None:
        paths = build_verifier_import_paths(None, None)
        self.assertEqual(paths, [])

    def test_task_root_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            paths = build_verifier_import_paths(task_root, None)
            # task_root and task_root.parent both exist; deduped
            self.assertIn(task_root, paths)

    def test_env_root_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_root = Path(tmp)
            utils_dir = env_root / "utils"
            utils_dir.mkdir()
            paths = build_verifier_import_paths(None, env_root)
            self.assertIn(env_root, paths)
            self.assertIn(utils_dir, paths)

    def test_env_root_utils_excluded_if_not_exists(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_root = Path(tmp)
            # utils/ does not exist
            paths = build_verifier_import_paths(None, env_root)
            self.assertIn(env_root, paths)
            self.assertNotIn(env_root / "utils", paths)

    def test_both_provided_no_duplicates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_env:
            with tempfile.TemporaryDirectory() as tmp_task:
                task_root = Path(tmp_task)
                env_root = Path(tmp_env)
                paths = build_verifier_import_paths(task_root, env_root)
                # All paths should be unique (no duplicate resolved paths)
                resolved = [str(p.resolve()) for p in paths]
                self.assertEqual(len(resolved), len(set(resolved)))

    def test_task_root_parent_included_when_exists(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            task_root = parent / "subtask"
            task_root.mkdir()
            paths = build_verifier_import_paths(task_root, None)
            self.assertIn(task_root, paths)
            self.assertIn(parent, paths)


class ListDefinedFunctionsTests(unittest.TestCase):
    """Tests for list_defined_functions."""

    def _write(self, tmp: str, source: str) -> Path:
        path = Path(tmp) / "module.py"
        path.write_text(source, encoding="utf-8")
        return path

    def test_finds_simple_function(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "def foo():\n    pass\n")
            funcs = list_defined_functions(path)
            self.assertIn("foo", funcs)

    def test_finds_multiple_functions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "def foo():\n    pass\ndef bar():\n    pass\n")
            funcs = list_defined_functions(path)
            self.assertIn("foo", funcs)
            self.assertIn("bar", funcs)

    def test_finds_async_function(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "async def async_func():\n    pass\n")
            funcs = list_defined_functions(path)
            self.assertIn("async_func", funcs)

    def test_empty_file_returns_empty_set(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "x = 1\n")
            funcs = list_defined_functions(path)
            self.assertNotIn("x", funcs)

    def test_nested_function_included(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "def outer():\n    def inner():\n        pass\n")
            funcs = list_defined_functions(path)
            self.assertIn("outer", funcs)
            self.assertIn("inner", funcs)

    def test_class_method_not_included_as_class(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "class Foo:\n    def method(self):\n        pass\n")
            funcs = list_defined_functions(path)
            # method is discovered (ast.walk traverses class body)
            self.assertIn("method", funcs)


class ListImportRootsTests(unittest.TestCase):
    """Tests for list_import_roots."""

    def _write(self, tmp: str, source: str) -> Path:
        path = Path(tmp) / "mod.py"
        path.write_text(source, encoding="utf-8")
        return path

    def test_simple_import(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "import os\n")
            roots = list_import_roots(path)
            self.assertIn("os", roots)

    def test_from_import(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "from pathlib import Path\n")
            roots = list_import_roots(path)
            self.assertIn("pathlib", roots)

    def test_dotted_import_uses_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "import os.path\n")
            roots = list_import_roots(path)
            self.assertIn("os", roots)
            self.assertNotIn("os.path", roots)

    def test_dotted_from_import_uses_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "from os.path import join\n")
            roots = list_import_roots(path)
            self.assertIn("os", roots)

    def test_relative_import_excluded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "from . import sibling\n")
            roots = list_import_roots(path)
            # Relative imports (level > 0) are excluded
            self.assertNotIn("sibling", roots)

    def test_no_imports_returns_empty(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "x = 42\n")
            roots = list_import_roots(path)
            self.assertEqual(roots, set())

    def test_multiple_imports(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(tmp, "import os\nimport sys\nfrom pathlib import Path\n")
            roots = list_import_roots(path)
            self.assertIn("os", roots)
            self.assertIn("sys", roots)
            self.assertIn("pathlib", roots)


class DiscoverLocalModulesTests(unittest.TestCase):
    """Tests for discover_local_modules."""

    def test_discovers_py_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            (task_root / "helper.py").write_text("", encoding="utf-8")
            modules = discover_local_modules(task_root, None)
            self.assertIn("helper", modules)

    def test_discovers_packages(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            pkg = task_root / "mypackage"
            pkg.mkdir()
            (pkg / "__init__.py").write_text("", encoding="utf-8")
            modules = discover_local_modules(task_root, None)
            self.assertIn("mypackage", modules)

    def test_dir_without_init_not_included(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            not_pkg = task_root / "notapkg"
            not_pkg.mkdir()
            modules = discover_local_modules(task_root, None)
            self.assertNotIn("notapkg", modules)

    def test_env_root_utils_also_searched(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env_root = Path(tmp)
            utils = env_root / "utils"
            utils.mkdir()
            (utils / "shared_utils.py").write_text("", encoding="utf-8")
            modules = discover_local_modules(None, env_root)
            self.assertIn("shared_utils", modules)

    def test_none_both_returns_empty(self) -> None:
        modules = discover_local_modules(None, None)
        self.assertEqual(modules, set())


class FindMissingImportsTests(unittest.TestCase):
    """Tests for find_missing_imports."""

    def _write(self, root: Path, name: str, source: str) -> Path:
        path = root / name
        path.write_text(source, encoding="utf-8")
        return path

    def test_stdlib_imports_not_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            path = self._write(task_root, "verifier.py", "import os\nimport sys\ndef verify(): pass\n")
            missing = find_missing_imports(path, task_root=task_root, env_root=None)
            self.assertEqual(missing, [])

    def test_local_module_not_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            (task_root / "utils.py").write_text("", encoding="utf-8")
            path = self._write(task_root, "verifier.py", "import utils\ndef verify(): pass\n")
            missing = find_missing_imports(path, task_root=task_root, env_root=None)
            self.assertNotIn("utils", missing)

    def test_missing_third_party_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            path = self._write(
                task_root,
                "verifier.py",
                "import definitely_missing_xyz_package_123\ndef verify(): pass\n",
            )
            missing = find_missing_imports(path, task_root=task_root, env_root=None)
            self.assertIn("definitely_missing_xyz_package_123", missing)

    def test_installed_package_not_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            path = self._write(task_root, "verifier.py", "import unittest\ndef verify(): pass\n")
            missing = find_missing_imports(path, task_root=task_root, env_root=None)
            self.assertNotIn("unittest", missing)

    def test_no_imports_returns_empty(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            path = self._write(task_root, "verifier.py", "def verify(): return True\n")
            missing = find_missing_imports(path, task_root=task_root, env_root=None)
            self.assertEqual(missing, [])

    def test_env_root_local_module_not_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_task:
            with tempfile.TemporaryDirectory() as tmp_env:
                task_root = Path(tmp_task)
                env_root = Path(tmp_env)
                utils = env_root / "utils"
                utils.mkdir()
                (utils / "env_helper.py").write_text("", encoding="utf-8")
                path = self._write(task_root, "verifier.py", "import env_helper\ndef verify(): pass\n")
                missing = find_missing_imports(path, task_root=task_root, env_root=env_root)
                self.assertNotIn("env_helper", missing)


class VerifierImportContextTests(unittest.TestCase):
    """Tests for verifier_import_context."""

    def test_adds_task_root_to_sys_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            original_path = list(sys.path)
            with verifier_import_context(task_root, None):
                self.assertIn(str(task_root.resolve()), sys.path)
            # Restored after exit
            self.assertEqual(sys.path, original_path)

    def test_restores_sys_path_on_exit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            original_path = list(sys.path)
            with verifier_import_context(task_root, None):
                pass
            self.assertEqual(sys.path, original_path)

    def test_restores_sys_path_on_exception(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            task_root = Path(tmp)
            original_path = list(sys.path)
            with self.assertRaises(ValueError):
                with verifier_import_context(task_root, None):
                    raise ValueError("test exception")
            self.assertEqual(sys.path, original_path)

    def test_none_inputs_no_error(self) -> None:
        original_path = list(sys.path)
        with verifier_import_context(None, None):
            pass
        self.assertEqual(sys.path, original_path)

    def test_both_task_and_env_added(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_task:
            with tempfile.TemporaryDirectory() as tmp_env:
                task_root = Path(tmp_task)
                env_root = Path(tmp_env)
                with verifier_import_context(task_root, env_root):
                    self.assertIn(str(task_root.resolve()), sys.path)
                    self.assertIn(str(env_root.resolve()), sys.path)


if __name__ == "__main__":
    unittest.main()
