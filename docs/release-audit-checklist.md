# Release Audit Checklist

This checklist is the release gate for verifying that the repository's public claims match the current codebase.

It is intentionally about release truthfulness and consistency:

- README and docs accuracy
- public API and CLI contract accuracy
- packaging and installability
- release-surface definition
- benchmark and verification claim accuracy
- service, security, and repo metadata accuracy

It is not a benchmark-quality, model-quality, or feature-adequacy checklist.

## How To Use This Checklist

- Run the audit against a specific commit or release candidate.
- Audit in a clean environment so install and packaging checks are meaningful.
- Mark each item as `pass`, `fail`, `waived`, or `out_of_scope`.
- Record concrete evidence for every `pass` such as command output, file references, screenshots, or issue links.
- Treat any failed blocker item as release-blocking unless the public claim is removed or narrowed before release.
- Any snapshot-based number or status claim must include an exact date.

## Audit Record

- Release candidate:
- Commit SHA:
- Audit date:
- Auditor:
- Supported release surface:
- Supported runners:
- Supported benchmark surface:
- Blocking findings:
- Waivers:

## 1. Release Scope And Promise

- [ ] README, docs overview, and packaging metadata describe the same release surface.
- [ ] The release explicitly states whether `src/gym_anything/`, `services/`, and `baselines/` are all in scope or whether some are reference-only.
- [ ] The release explicitly states whether the supported benchmark surface is the raw corpus or the verifier-backed surface in `benchmarks/splits/verified.json`.
- [ ] Supported runners are named consistently across README, docs, CLI docs, and compatibility docs.
- [ ] Experimental or reference-only surfaces are labeled as such everywhere they are mentioned.
- [ ] Version, release scope, and compatibility promises are written as current facts, not implied aspirations.
- [ ] Placeholder metadata is removed from public-facing files such as repo URLs, install placeholders, and example organization names.

## 2. README And Docs Truth Audit

- [ ] Every command shown in `README.md` and `docs/` either works as written or is clearly marked illustrative.
- [ ] Every environment id and task id used in examples exists in the repo.
- [ ] Every file link and page link in docs resolves to an existing file.
- [ ] The README and docs use the same canonical action format and observation vocabulary as the runtime.
- [ ] The README and docs do not claim support for behavior that is only present in baselines or experimental code.
- [ ] The same feature is not described differently across pages without an explicit caveat.
- [ ] Snapshot claims such as task counts and verification totals are either current or explicitly dated.
- [ ] The limitations page includes all known release-relevant caveats discovered during the audit.
- [ ] There are no obvious stale placeholders or unfinished notes such as `<repo-url>`, `example.com`, `TODO`, `TBD`, or `FIXME` in public-facing docs.

Suggested evidence commands:

```bash
rg -n "<repo-url>|example\\.com|TODO|TBD|FIXME" README.md docs mkdocs.yml pyproject.toml
rg -n "create_saved_search|verified.json|use_savevm|RemoteGymEnv" README.md docs src tests
```

## 3. Packaging, Build, And Installability

- [ ] `pip install -e .` succeeds in a clean virtual environment on the documented Python version.
- [ ] Optional extras `.[services]`, `.[baselines]`, and `.[vlm]` install successfully or are explicitly documented as optional and environment-dependent.
- [ ] Building release artifacts succeeds with sdist and wheel output.
- [ ] Console entry points declared in `pyproject.toml` import successfully and show help output.
- [ ] Required package data is included in build artifacts, especially presets, runner definitions, and benchmark split files.
- [ ] Runtime dependencies in `pyproject.toml` match what the documented public surface imports at runtime.
- [ ] `requires-python` matches the docs and the tested release environment.
- [ ] Packaging metadata is suitable for public release, including name, version, description, and real project URLs.

Suggested evidence commands:

```bash
python -m pip install -e .
python -m pip install -e ".[services]"
python -m pip install -e ".[baselines]"
python -m pip install -e ".[vlm]"
python -m build
gym-anything --help
gym-anything-master --help
gym-anything-worker --help
gym-anything-dashboard --help
```

## 4. Public API And CLI Contract

- [ ] All symbols documented as public imports are importable from `gym_anything`.
- [ ] Documented constructor and method signatures match the actual code.
- [ ] CLI subcommands and flags documented in README and `docs/cli.md` exist and behave as described.
- [ ] The public API does not require users to call private helpers.
- [ ] `RemoteGymEnv` exposes the documented public methods and matches the documented reset semantics.
- [ ] The documented compatibility helpers exist and return data for the claimed runners.
- [ ] Public API contract tests pass.

Suggested evidence commands:

```bash
python -m pytest tests/test_public_api_contract.py tests/test_remote_client.py tests/test_compatibility.py
PYTHONPATH=src python -m gym_anything.cli --help
PYTHONPATH=src python -m gym_anything.cli compatibility --help
PYTHONPATH=src python -m gym_anything.cli verify --help
PYTHONPATH=src python -m gym_anything.cli doctor --help
```

## 5. Runtime Semantics And Compatibility Claims

- [ ] Runner selection behavior in docs matches the current selection logic in `GymAnythingEnv`.
- [ ] The compatibility matrix matches code and tests for recording, checkpoint caching, `use_savevm`, and `user_accounts`.
- [ ] `reset()`, `step()`, `mark_done=True`, and `close()` behavior are described consistently across README, API docs, and tests.
- [ ] Caching behavior and fallback behavior are described accurately.
- [ ] Observation modalities in docs match the observation builder output.
- [ ] Canonical action examples in docs match current runner expectations.
- [ ] `doctor`, `validate`, `verify spec`, `verify corpus`, `verify task`, and `run` are documented consistently with the CLI implementation.
- [ ] Features that are descriptive-only in the spec are not presented as enforced runtime behavior.

Suggested evidence commands:

```bash
python -m pytest tests/test_env_runtime_behaviors.py tests/test_doctor.py tests/test_verification_system.py tests/test_worker_reset_policy.py
PYTHONPATH=src python -m gym_anything.cli compatibility --json
PYTHONPATH=src python -m gym_anything.cli doctor --json
```

## 6. Benchmark Corpus And Verification Claims

- [ ] README corpus counts match the current repo or are explicitly labeled as a dated snapshot.
- [ ] Verification totals in docs match a fresh audit run or are explicitly labeled as a dated snapshot.
- [ ] The verifier-backed supported surface in `benchmarks/splits/verified.json` exists and is described consistently.
- [ ] Example environments and tasks used in docs load through `from_config`.
- [ ] Declared verifier modes in docs, validators, and runtime are the same.
- [ ] Known missing hook references, missing verifier dependencies, or similar corpus issues are either outside the release surface or explicitly documented.
- [ ] Split registry behavior for raw versus verified surfaces is documented consistently with code and tests.

Suggested evidence commands:

```bash
python - <<'PY'
from pathlib import Path
root = Path("benchmarks/environments")
env_specs = sum(1 for _ in root.glob("*/env.json")) + sum(1 for _ in root.glob("*/env.yaml"))
task_specs = sum(1 for _ in root.glob("*/tasks/*/task.json")) + sum(1 for _ in root.glob("*/tasks/*/task.yaml")) + sum(1 for _ in root.glob("*/tasks/*/task.yml"))
print({"env_specs": env_specs, "task_specs": task_specs})
PY
PYTHONPATH=src python -m gym_anything.cli verify spec benchmarks/environments/zotero_env --task create_saved_search
PYTHONPATH=src python -m gym_anything.cli verify corpus benchmarks/environments --json
python -m pytest tests/test_benchmark_registry.py tests/test_verification_status.py
```

## 7. Services And Remote Execution

- [ ] `services/master`, `services/worker`, and `services/dashboard` are either in release scope and smoke-tested or clearly documented as optional advanced components.
- [ ] Service entry points start and expose the documented CLI surface.
- [ ] Worker default reset behavior matches the documented `core` parity path.
- [ ] `RemoteGymEnv` documentation matches the worker and master API behavior.
- [ ] Remote-only caveats such as worker-side path semantics are documented where users will see them.
- [ ] If services are public in this release, installation and minimal smoke flow are part of the release evidence.

Suggested evidence commands:

```bash
python -m services.master.app --help
python -m services.worker.app --help
python -m services.dashboard.app --help
python -m pytest tests/test_remote_client.py tests/test_worker_reset_policy.py
```

## 8. Security, Secrets, And Repository Hygiene

- [ ] No secrets, tokens, private endpoints, or internal credentials are committed in release-facing files.
- [ ] Example or benchmark-local passwords are clearly framed as local fixture credentials, not secure defaults.
- [ ] Security docs distinguish between enforced controls, compatibility metadata, and unsupported fields.
- [ ] Secret-loading behavior such as `security.secrets_ref` is documented accurately.
- [ ] Repo metadata does not contain placeholder URLs or placeholder ownership information.
- [ ] Public release includes a clear licensing story for the project and for material under `third_party/`.
- [ ] Any vendored or third-party artifacts have provenance or notice documentation suitable for release.

Suggested evidence commands:

```bash
rg -n "AKIA|AIza|sk-|password123|example\\.com|secrets_ref" README.md docs src services baselines benchmarks pyproject.toml
ls -1 LICENSE* third_party
```

## 9. Tests, CI, And Reproducibility

- [ ] Release-critical tests pass locally.
- [ ] There is CI coverage for release-critical checks, or the release process explicitly defines a manual replacement gate.
- [ ] Docs build cleanly.
- [ ] The release process captures audit evidence artifacts such as command transcripts or JSON outputs.
- [ ] The audit result is attached to the release candidate and references the exact commit audited.

Suggested evidence commands:

```bash
python -m pytest tests
mkdocs build --strict
```

## 10. Release Decision Gate

- [ ] Every blocker item above is `pass`, `waived`, or explicitly removed from the public claim set before tagging.
- [ ] Every `waived` item has an owner, follow-up issue, and user-facing caveat.
- [ ] The final release notes match the actual supported surface and caveats.
- [ ] The release tag is cut from the audited commit, not a later unreviewed state.

## Minimum Audit Artifacts To Save

- The completed checklist with pass/fail status.
- The exact commit SHA audited.
- Command output for install, build, CLI help, and chosen verification runs.
- Test results for the release-critical test set.
- A short list of blockers, waivers, and follow-up issues.
