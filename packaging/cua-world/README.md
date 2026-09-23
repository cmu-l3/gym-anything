# cua-world

CUA-World as one package, so the core `gym-anything` package ships without
the ~79k-file corpus:

- `benchmarks.cua_world` is the corpus: environments, tasks, splits and the
  thin registry binding. `--benchmark cua_world` (the default) resolves it.
- `cua_world` holds its hub entry points. `load_environment` is the Prime
  Intellect verifiers environment (`vf-eval cua-world`), and the `cua-world`
  command (`cua_world.main`) is the Harbor adapter. The source lives in
  `extras/hubs/harbor/cua_world/src/cua_world/`.

Install it with core from gym-anything's main branch:

```bash
pip install "cua-world @ git+https://github.com/cmu-l3/gym-anything@main#subdirectory=packaging/cua-world"
```

Core without this package errors actionably: install `cua-world` or pass
`--benchmark <name-or-path>` for another corpus. In a repo checkout nothing
changes for core: `benchmarks/` resolves from the working directory as before.

To run the Prime environment or the Harbor adapter from a checkout, install
core editable first and then this package without dependencies:

```bash
uv pip install -e ".[modal,prime-rl,benchmark,agents]"   # from repo root
uv pip install --no-deps packaging/cua-world
```

Hatchling copies force-included files even into editable wheels, so this is
a regular install: reinstall it after changing the hub code.

Build from this directory (`hatchling` pulls the corpus and the hub package
from the repo tree via force-include): `python -m build packaging/cua-world`.

Release hygiene: the version here and in the root `pyproject.toml` must
match the release tag; assert both in release CI before publishing.
