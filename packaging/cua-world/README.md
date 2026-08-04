# cua-world

The CUA-World benchmark corpus (`benchmarks/cua_world/`: environments,
tasks, splits, and the thin registry binding) as its own distribution, so
the core `gym-anything` package ships without the ~79k-file corpus.

- `pip install gym-anything cua-world` — core plus the default benchmark;
  `--benchmark cua_world` (the default) resolves via `benchmarks.cua_world`.
- Core without this package errors actionably: install `cua-world` or pass
  `--benchmark <name-or-path>` for another corpus.
- In a repo checkout nothing changes: `benchmarks/` resolves from the
  working directory as before.

Build from this directory (`hatchling` pulls the corpus from the repo tree
via force-include): `python -m build packaging/cua-world`.

Release hygiene: the version here and in the root `pyproject.toml` must
match the release tag; assert both in release CI before publishing.
