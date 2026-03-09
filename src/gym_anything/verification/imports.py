from __future__ import annotations

import ast
import contextlib
import importlib.util
import sys
from functools import lru_cache
from pathlib import Path
from typing import Iterator, List, Optional, Set


def _dedupe_paths(paths: List[Path]) -> List[Path]:
    seen: Set[str] = set()
    ordered: List[Path] = []
    for path in paths:
        resolved = str(path.resolve())
        if resolved in seen:
            continue
        seen.add(resolved)
        ordered.append(path)
    return ordered


def build_verifier_import_paths(task_root: Optional[Path], env_root: Optional[Path]) -> List[Path]:
    candidates: List[Path] = []
    if task_root:
        candidates.append(task_root)
        candidates.append(task_root.parent)
    if env_root:
        candidates.append(env_root)
        candidates.append(env_root / "utils")
    existing = [candidate for candidate in candidates if candidate.exists()]
    return _dedupe_paths(existing)


@lru_cache(maxsize=None)
def _parse_module(path_str: str) -> ast.AST:
    path = Path(path_str)
    return ast.parse(path.read_text(encoding="utf-8"), filename=str(path))


def list_defined_functions(path: Path) -> Set[str]:
    tree = _parse_module(str(path.resolve()))
    return {
        node.name
        for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }


def list_import_roots(path: Path) -> Set[str]:
    tree = _parse_module(str(path.resolve()))
    imports: Set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.add(alias.name.split(".", 1)[0])
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            imports.add(node.module.split(".", 1)[0])
    return imports


def discover_local_modules(task_root: Optional[Path], env_root: Optional[Path]) -> Set[str]:
    modules: Set[str] = set()
    for base in build_verifier_import_paths(task_root, env_root):
        for child in base.iterdir():
            if child.is_file() and child.suffix == ".py":
                modules.add(child.stem)
            elif child.is_dir() and (child / "__init__.py").exists():
                modules.add(child.name)
    return modules


def find_missing_imports(path: Path, task_root: Optional[Path], env_root: Optional[Path]) -> List[str]:
    stdlib = set(getattr(sys, "stdlib_module_names", ()))
    local_modules = discover_local_modules(task_root, env_root)
    missing: List[str] = []
    for module_name in sorted(list_import_roots(path)):
        if module_name in stdlib:
            continue
        if module_name in local_modules:
            continue
        if importlib.util.find_spec(module_name) is not None:
            continue
        missing.append(module_name)
    return missing


@contextlib.contextmanager
def verifier_import_context(task_root: Optional[Path], env_root: Optional[Path]) -> Iterator[None]:
    paths = [str(path.resolve()) for path in build_verifier_import_paths(task_root, env_root)]
    original_sys_path = list(sys.path)
    try:
        for path in reversed(paths):
            if path not in sys.path:
                sys.path.insert(0, path)
        yield
    finally:
        sys.path[:] = original_sys_path


__all__ = [
    "build_verifier_import_paths",
    "discover_local_modules",
    "find_missing_imports",
    "list_defined_functions",
    "list_import_roots",
    "verifier_import_context",
]
