# Release Readiness Tracker

Use [Release Audit Checklist](release-audit-checklist.md) as the actual release gate for public-claim accuracy and consistency.

This page is a tracker for workstreams and open questions. It is not the audit instrument and may contain historical status notes.

This file tracks the work required to move Gym-Anything from a strong research codebase to a release-ready public runtime without breaking the current benchmark corpus.

## Principles

- Preserve compatibility for existing environment and task directories under `benchmarks/cua_world/environments/`.
- Prefer additive API changes over breaking changes.
- Do not document a feature as supported unless it is implemented, validated, and tested.
- Keep `baselines/` usable as reference code, but prevent baseline-only behavior from leaking into the product runtime.

## Current Status

### Completed

- Repository layout has been separated into `src/`, `benchmarks/`, `baselines/`, `services/`, `tools/`, and `docs/`.
- The docs now call out current implementation gaps explicitly instead of implying support.
- Benchmark and tutorial content now live in separate top-level areas.
- `TaskSpec` preserves common top-level task metadata and keeps additional unmodeled keys in `extras`.
- Public `capture_observation()` methods exist on local and remote environments.
- `RemoteGymEnv.reset()` now accepts `cache_level` and `use_savevm`.
- A compatibility test module exists for the first public API contract tranche.
- Verification is now a first-class package surface under `gym_anything.verification`, with CLI entrypoints for `verify spec`, `verify corpus`, and `verify task`.
- Unsupported verifier modes have been removed from the public verifier contract instead of being silently accepted.
- Benchmark split definitions now live in `benchmarks/cua_world/splits/*.json`, with a compatibility wrapper for older `benchmarks.cua_world.registry.task_splits` imports.
- The verifier-backed supported task surface is published in `benchmarks/cua_world/splits/verified.json`.
- The baseline evaluation harnesses now use the JSON-backed split registry and configurable VLM settings.
- Worker reset now defaults to `core` parity, with an explicit `baseline_setup` policy for baseline-oriented worker-side setup.
- `BrowserRunner` is now reachable through runner selection.
- `close()` now runs `post_task` and verification for unfinished episodes.
- Non-Docker runs can now assemble `recording.mp4` from step screenshots when host `ffmpeg` is available.
- `pyproject.toml` now declares the shipped runtime dependencies and packages the service and baseline modules that the repo documents.
- A first-class compatibility contract now exists for runner capability differences, with CLI and Python API access.
- `reward_type` now supports `partial`, `rubric`, and `continuous` final reward semantics.
- post-reset setup logic now lives in the product runtime instead of only in `baselines`.
- `security.secrets_ref` now resolves host-side secret bundles into runner execution environments.
- `gym-anything doctor` now checks runner-specific system prerequisites and can scan verifier imports statically.

### In Progress

- Productizing the public Python and remote APIs while preserving current environment compatibility.
- Productizing the verification and validation system as a release gate.

### Newly Discovered Issues

- As of March 8, 2026, `gym-anything verify corpus benchmarks/cua_world/environments` reports `7,277` verified tasks and `385` failed tasks.
- All currently reported corpus failures are `missing_hook_reference` issues caused by tasks that reference absent setup/export scripts.
- The current hook-asset backlog is tracked in `benchmarks/cua_world/splits/missing_hook_references.json` and `benchmarks/cua_world/splits/missing_hook_task_dirs.txt`.
- Corpus verification still exposes undeclared verifier import dependencies in environments outside the currently failing hook-reference slice.

### Not Started

- Capability-matrix enforcement across runners.
- CI coverage for public release workflows.

## Workstreams

### 1. Public API And Spec Model

Status: `partially_completed`

- Add missing top-level task metadata to `TaskSpec` without breaking existing task loading.
- Add public observation-capture APIs so baselines and services stop using private helpers.
- Align `RemoteGymEnv` method signatures with `GymAnythingEnv` where behavior is already supported.
- Add compatibility tests for common `env.json` and `task.json` fields used in the corpus.

### 2. Verification Contract

Status: `partially_completed`

- Remove unsupported verifier modes from the public schema.
- Tighten validation so declared verifier modes cannot drift from implementation.
- Keep spec verification, corpus verification, and task-pipeline verification inside the product package and CLI.
- Continue hardening verifier dependency auditing and hook-reference auditing.

### 3. Runner Capability Consistency

Status: `in_progress`

- Define and publish a runner capability matrix for Docker, QEMU, AVD, direct Apptainer, browser, and local smoke mode.
- Replace fixed waits with readiness checks where possible.
- Decide which runners officially support recording, checkpointing, user accounts, accessibility tree capture, and audio capture.

Open decisions:

- Should browser workloads be a first-class runner in the initial release?
- Do we want a release that includes direct Apptainer as supported, or should it remain experimental until checkpoint/audio gaps are resolved?

### 4. Services And Remote Execution

Status: `partially_completed`

- Make `core` parity the default worker reset behavior.
- Keep baseline-oriented worker setup explicit instead of hidden default behavior.
- Keep remote and local semantics aligned for reset, capture, and lifecycle behavior.
- Version and document the remote API surface.

### 5. Packaging And Installation

Status: `partially_completed`

- Add real runtime dependencies and optional extras to `pyproject.toml`.
- Add console entry points for supported CLIs and services.
- Make installation paths explicit for core runtime, services, and optional runner backends.

### 6. Validation, Testing, And CI

Status: `in_progress`

- Replace minimal structural validation with stronger schema and capability-aware validation.
- Add tests for loader compatibility across representative benchmark environments.
- Add smoke coverage for CLI, remote client/server flows, and key runners.
- Add docs-link and packaging-install checks in CI.
- Add coverage for the JSON-backed split registry and verified benchmark surface.

### 7. Security And Operational Controls

Status: `in_progress`

- Audit all declared security fields and determine which are enforced vs descriptive.
- Unsupported public security controls such as `network_allowlist` and `secrets_ref` now fail fast in validation; full implementations are still pending.
- Define a supported secret-loading pattern for local runs and services.

## Immediate Execution Plan

The first implementation tranche is intentionally compatibility-safe:

1. Preserve top-level task metadata fields in `TaskSpec`.
2. Add public observation-capture methods and stop using `_capture_observation()` from public-facing code.
3. Align remote reset arguments with local reset arguments.
4. Turn verification into a first-class product subsystem instead of scattered maintenance logic.
5. Update docs and this tracker as those changes land.

## Compatibility Constraints

- Existing `task.json` files with top-level `description` and `version` must keep working.
- Existing remote clients that call `reset(seed=..., use_cache=...)` must keep working unchanged.
- Existing baseline scripts must continue to run during the migration, even if internals are being cleaned up underneath them.

## Open Questions For Product Release

- What is the exact supported surface for `v0.1`: just the runtime library, or runtime plus services?
- Which runners are officially supported in `v0.1`?
- Should benchmark-specific convenience behavior live in `baselines/` only, or do we want a first-class “reset policy” concept in the product?
