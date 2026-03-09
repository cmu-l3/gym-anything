#!/usr/bin/env python3
"""Audit canonical repository structure."""

from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
BENCHMARK_ENVS = ROOT / "benchmarks" / "environments"

ALLOWED_ENV_FILES = {
    "README.md",
    "QUICKSTART.md",
    "env.json",
    "env.yaml",
}

ALLOWED_ENV_DIRS = {
    "addons",
    "artifacts",
    "assets",
    "config",
    "data",
    "dev",
    "docs",
    "evidence",
    "metadata",
    "scripts",
    "tasks",
    "utils",
}

BYPRODUCT_SUFFIXES = {".pyc", ".pyo"}
BYPRODUCT_NAMES = {".DS_Store"}
DISALLOWED_ENV_SUFFIXES = ("_bak", "_final", "_copy", "_legacy")
TUTORIAL_ENVS = {"simple_user_setup", "user_permissions_demo"}


def main() -> int:
    issues: list[str] = []

    if not BENCHMARK_ENVS.is_dir():
        issues.append("Missing benchmarks/environments directory.")
        return finish(issues)

    for path in ROOT.rglob("*"):
        if any(part == ".git" for part in path.parts):
            continue
        if path.name == "__pycache__":
            issues.append(rel(path))
            continue
        if path.is_file() and (path.suffix in BYPRODUCT_SUFFIXES or path.name in BYPRODUCT_NAMES):
            issues.append(rel(path))

    for path in sorted(BENCHMARK_ENVS.iterdir()):
        if path.is_file() and path.name != "__init__.py":
            issues.append(f"Loose file at benchmarks/environments root: {rel(path)}")

    for env_dir in sorted(p for p in BENCHMARK_ENVS.iterdir() if p.is_dir()):
        if env_dir.name.endswith(DISALLOWED_ENV_SUFFIXES):
            issues.append(f"Archived variant still in canonical benchmark set: {rel(env_dir)}")
        if env_dir.name in TUTORIAL_ENVS:
            issues.append(f"Tutorial environment still in benchmark corpus: {rel(env_dir)}")

        for child in sorted(env_dir.iterdir()):
            if child.is_file() and child.name not in ALLOWED_ENV_FILES:
                issues.append(f"Non-canonical env-root file: {rel(child)}")
            elif child.is_dir() and child.name not in ALLOWED_ENV_DIRS:
                issues.append(f"Non-canonical env-root directory: {rel(child)}")

    return finish(issues)


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def finish(issues: list[str]) -> int:
    if not issues:
        print("Structure audit passed.")
        return 0

    print("Structure audit failed:")
    for issue in issues:
        print(f"- {issue}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
