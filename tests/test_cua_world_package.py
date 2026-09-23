"""The cua-world distribution (packaging/cua-world): one package for CUA-World.

It ships the corpus (``benchmarks.cua_world``) and the hub entry points
(``cua_world``: Prime Intellect's ``load_environment`` and the Harbor adapter).
These tests keep it whole: no second distribution may take its name, and no
corpus directory shared by symlink may drop out of the wheel.
"""

from __future__ import annotations

import os
import subprocess
import sys
import unittest
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python 3.10: tomllib landed in 3.11
    import tomli as tomllib

REPO_ROOT = Path(__file__).resolve().parents[1]
PACKAGE_DIR = REPO_ROOT / "packaging" / "cua-world"
CORPUS = REPO_ROOT / "benchmarks" / "cua_world"


def _pyproject(path: Path) -> dict:
    with open(path, "rb") as fh:
        return tomllib.load(fh)


class DistributionNamesTest(unittest.TestCase):
    def test_every_distribution_in_the_repo_has_its_own_name(self) -> None:
        listed = subprocess.run(
            ["git", "ls-files", "-z", "*pyproject.toml"],
            cwd=REPO_ROOT, capture_output=True, text=True, check=True,
        ).stdout.split("\0")
        # Corpus content (sample repositories inside tasks) is not ours to package.
        paths = [REPO_ROOT / p for p in listed if p and "/environments/" not in p]
        names = [_pyproject(p)["project"]["name"] for p in paths]
        self.assertIn("cua-world", names)
        self.assertEqual(len(names), len(set(names)), dict(zip(map(str, paths), names)))


class SymlinkedCorpusDirectoriesTest(unittest.TestCase):
    def test_every_symlinked_directory_is_mapped_explicitly(self) -> None:
        build = _pyproject(PACKAGE_DIR / "pyproject.toml")["tool"]["hatch"]["build"]["targets"]
        for target in ("wheel", "sdist"):
            mapped = {
                os.path.normpath(PACKAGE_DIR / source): dest
                for source, dest in build[target]["force-include"].items()
            }
            for dirpath, dirnames, _files in os.walk(CORPUS):
                for name in dirnames:
                    link = Path(dirpath) / name
                    if not link.is_symlink():
                        continue
                    dest = "benchmarks/" + link.relative_to(REPO_ROOT / "benchmarks").as_posix()
                    self.assertEqual(
                        mapped.get(os.path.normpath(link.resolve())), dest,
                        f"{target}: {link} is a symlink; map its target to {dest}",
                    )


class HubEntryPointsTest(unittest.TestCase):
    def test_cua_world_serves_prime_and_harbor(self) -> None:
        sys.path.insert(0, str(REPO_ROOT / "extras" / "hubs" / "harbor" / "cua_world" / "src"))
        try:
            import cua_world
            from cua_world import main
        finally:
            sys.path.pop(0)
        self.assertTrue(callable(cua_world.load_environment))
        self.assertTrue(callable(main.main))
        scripts = _pyproject(PACKAGE_DIR / "pyproject.toml")["project"]["scripts"]
        self.assertEqual(scripts, {"cua-world": "cua_world.main:main"})


if __name__ == "__main__":
    unittest.main()
