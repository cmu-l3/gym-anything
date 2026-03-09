# Maintenance

## Documentation Hygiene

The docs are only useful if they stay grounded in the code.

When behavior changes:

- update the relevant doc page immediately
- remove stale claims rather than leaving contradictory notes in multiple files
- prefer explicit limitations over silent omissions
- delete stale implementation logs and speculative writeups instead of keeping shadow docs

## Benchmark Hygiene

For `benchmarks/environments/`:

- keep runtime files separate from audit material
- keep `docs/` for environment-local guides and snippets
- keep `dev/` for local validation harnesses and one-off test scripts
- keep `metadata/` for status and review documents
- keep `evidence/` for screenshots and validation outputs
- move stray temporary files out of canonical environment roots

Run the structure audit before calling a cleanup pass complete:

```bash
PYTHONDONTWRITEBYTECODE=1 python scripts/maintenance/audit_repo_structure.py
```

Run the spec-loading audit before calling a benchmark ingest or release pass complete:

```bash
PYTHONPATH=src python -m gym_anything.cli verify corpus benchmarks/environments
```

The release-backed benchmark surface is regenerated with:

```bash
PYTHONPATH=src python -m gym_anything.cli verify corpus \
  benchmarks/environments \
  --write-status-manifest benchmarks/splits/verification_status.json \
  --write-verified-split benchmarks/splits/verified.json \
  --write-missing-hook-manifest benchmarks/splits/missing_hook_references.json
```

For quick triage of the current hook-asset backlog, use:

- `benchmarks/splits/missing_hook_references.json` for structured task and asset details
- `benchmarks/splits/missing_hook_task_dirs.txt` for a flat list of task directory paths

The compatibility wrapper script still exists:

```bash
PYTHONPATH=src python scripts/maintenance/audit_spec_loading.py
```

but the package CLI is the canonical interface.

## Spec Hygiene

If contributors add fields to JSON files that the runtime should actually use:

- add them to the relevant dataclass
- plumb them through loaders and consumers
- document them in [Specs](specs.md)

If a field is just corpus metadata, keep it documented as metadata rather than pretending it is part of the runtime contract.

## Release Hygiene

Before cutting a public release or publishing benchmark results:

- re-check benchmark counts if you report them
- verify runner support claims
- verify verifier mode claims
- verify packaging/install instructions still match the repo

## Recommended Periodic Audits

- scan docs for broken local links
- scan docs for old paths or deleted scripts
- run `scripts/maintenance/audit_repo_structure.py`
- compare declared spec fields against actual runner usage
- compare benchmark JSON conventions against what `TaskSpec` and `EnvSpec` preserve
- compare `benchmarks/splits/verified.json` against the currently published benchmark surface
