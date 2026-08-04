#!/usr/bin/env python3
"""Release hygiene: assert a release tag matches both distributions' versions.

Run in release CI on tag push (needs `workflow`-scoped credentials to add
the workflow; the job is one step):

    python packaging/release_check.py "${GITHUB_REF_NAME#v}"
"""
import sys
import tomllib

tag = sys.argv[1]
failures = []
for path in ("pyproject.toml", "packaging/cua-world/pyproject.toml"):
    with open(path, "rb") as fh:
        version = tomllib.load(fh)["project"]["version"]
    if version != tag:
        failures.append(f"{path} has version {version}, tag is {tag}")
if failures:
    raise SystemExit("\n".join(failures))
print(f"tag v{tag} matches both distributions")
