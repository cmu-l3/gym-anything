"""Dispatcher for the `gym-anything-extras` command.

Extras live outside the gym-anything library proper — they are
contract-respecting consumers/producers of env.json/task.json/etc., not
part of the runtime API. This dispatcher discovers them by walking the
`extras/` directory at the repo root and forwarding argv to a registered
method's `run(argv)` callable.

A method is anything matching:

    extras/<group>/<category>/<method>/method.py

with a top-level `run(argv: list[str] | None) -> int` function. The CLI
maps to:

    gym-anything-extras <group> <category> <method> [args...]

Examples:

    gym-anything-extras                               # list groups
    gym-anything-extras research                      # list categories under research/
    gym-anything-extras research software_as_env     # list methods
    gym-anything-extras research software_as_env creation_audit --help

This dispatcher imports nothing from the methods until they are invoked,
so missing optional dependencies for one method don't break listing
others.
"""

from __future__ import annotations

import argparse
import importlib
import importlib.util
import os
import sys
from pathlib import Path
from typing import Iterable, List, Optional, Tuple


def _find_extras_root() -> Optional[Path]:
    """Locate the `extras/` directory.

    Honors GYM_ANYTHING_EXTRAS_ROOT, then walks upward from this file
    looking for an `extras/` sibling next to a `src/gym_anything/` tree.
    """
    override = os.environ.get("GYM_ANYTHING_EXTRAS_ROOT")
    if override:
        path = Path(override).resolve()
        return path if path.is_dir() else None

    here = Path(__file__).resolve()
    for ancestor in here.parents:
        candidate = ancestor / "extras"
        if candidate.is_dir() and (ancestor / "src" / "gym_anything").is_dir():
            return candidate
    # Fallback: walk just for an `extras/` dir without requiring the src layout.
    for ancestor in here.parents:
        candidate = ancestor / "extras"
        if candidate.is_dir():
            return candidate
    return None


def _list_subdirs(path: Path) -> List[str]:
    if not path.is_dir():
        return []
    return sorted(
        p.name for p in path.iterdir()
        if p.is_dir() and not p.name.startswith((".", "_"))
    )


def _find_method(extras_root: Path, parts: Tuple[str, ...]) -> Optional[Path]:
    """Resolve method.py under extras_root/parts/."""
    candidate = extras_root.joinpath(*parts) / "method.py"
    return candidate if candidate.is_file() else None


def _print_listing(label: str, items: Iterable[str], usage_hint: str = "") -> None:
    items = list(items)
    print(label)
    if not items:
        print("  (none)")
    else:
        for item in items:
            print(f"  {item}")
    if usage_hint:
        print()
        print(usage_hint)


def _import_method(method_path: Path):
    """Import method.py as a module without polluting sys.path."""
    module_name = "gym_anything_extras_method_" + str(abs(hash(str(method_path))))
    spec = importlib.util.spec_from_file_location(module_name, method_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load method module from {method_path}")
    module = importlib.util.module_from_spec(spec)

    # Make the package the method lives in importable so it can use
    # relative imports (`from .helpers import ...`). We do this by adding
    # the parent of the *top-level* package to sys.path, mirroring how
    # `python -m extras.research.X.Y.method` would behave.
    extras_root = method_path
    while extras_root.parent.name and extras_root.parent.name != "extras":
        extras_root = extras_root.parent
    repo_root = extras_root.parent.parent if extras_root.parent.name == "extras" else None
    if repo_root and str(repo_root) not in sys.path:
        sys.path.insert(0, str(repo_root))

    # Some module-level decorators (notably dataclasses on Python 3.13)
    # resolve the module through sys.modules while the file is executing.
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(module_name, None)
        raise
    return module


def _discover(extras_root: Path) -> dict:
    """Build a 3-level map: group → category → [methods]."""
    tree: dict = {}
    for group_dir in sorted(p for p in extras_root.iterdir() if p.is_dir() and not p.name.startswith((".", "_"))):
        categories: dict = {}
        for cat_dir in sorted(p for p in group_dir.iterdir() if p.is_dir() and not p.name.startswith((".", "_"))):
            methods = []
            for method_dir in sorted(p for p in cat_dir.iterdir() if p.is_dir() and not p.name.startswith((".", "_"))):
                if (method_dir / "method.py").is_file():
                    methods.append(method_dir.name)
            if methods:
                categories[cat_dir.name] = methods
        if categories:
            tree[group_dir.name] = categories
    return tree


def main(argv: Optional[List[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    extras_root = _find_extras_root()
    if extras_root is None:
        print(
            "extras/ directory not found. Set GYM_ANYTHING_EXTRAS_ROOT or "
            "run from inside a gym-anything checkout.",
            file=sys.stderr,
        )
        return 1

    # Top-level help: avoid argparse capturing things meant for the sub-method.
    if argv and argv[0] in ("-h", "--help"):
        tree = _discover(extras_root)
        print("Usage: gym-anything-extras <group> <category> <method> [args...]")
        print()
        print("These are research and adjacent tools that consume/produce gym-anything")
        print("artifacts (env.json, task.json, *_split.json, ...) but are not part of")
        print("the gym-anything library. Run a method with `--help` for its own flags.")
        print()
        print(f"extras root: {extras_root}")
        print()
        if not tree:
            print("(no methods discovered)")
            return 0
        for group, cats in tree.items():
            print(f"  {group}/")
            for cat, methods in cats.items():
                print(f"    {cat}/")
                for method in methods:
                    print(f"      {method}")
        return 0

    tree = _discover(extras_root)

    # No args: list groups
    if not argv:
        _print_listing(
            "Available groups under extras/:",
            tree.keys(),
            "Run `gym-anything-extras <group>` to list categories.",
        )
        return 0

    group = argv[0]
    if group not in tree:
        print(f"Unknown group: {group!r}. Available: {', '.join(tree) or '(none)'}", file=sys.stderr)
        return 2

    # One arg: list categories in group
    if len(argv) == 1:
        _print_listing(
            f"Categories under {group}/:",
            tree[group].keys(),
            f"Run `gym-anything-extras {group} <category>` to list methods.",
        )
        return 0

    category = argv[1]
    if category not in tree[group]:
        print(
            f"Unknown category: {category!r} under {group}/. "
            f"Available: {', '.join(tree[group]) or '(none)'}",
            file=sys.stderr,
        )
        return 2

    # Two args: list methods
    if len(argv) == 2:
        _print_listing(
            f"Methods under {group}/{category}/:",
            tree[group][category],
            f"Run `gym-anything-extras {group} {category} <method> --help` for details.",
        )
        return 0

    method = argv[2]
    if method not in tree[group][category]:
        print(
            f"Unknown method: {method!r} under {group}/{category}/. "
            f"Available: {', '.join(tree[group][category]) or '(none)'}",
            file=sys.stderr,
        )
        return 2

    method_path = _find_method(extras_root, (group, category, method))
    if method_path is None:
        print(f"method.py missing at extras/{group}/{category}/{method}/", file=sys.stderr)
        return 2

    module = _import_method(method_path)
    runner = getattr(module, "run", None)
    if runner is None or not callable(runner):
        print(
            f"extras/{group}/{category}/{method}/method.py has no callable run(argv).",
            file=sys.stderr,
        )
        return 2

    try:
        result = runner(argv[3:])
    except SystemExit as exc:
        return int(exc.code or 0)
    except KeyboardInterrupt:
        return 130
    return int(result or 0)


if __name__ == "__main__":
    raise SystemExit(main())
