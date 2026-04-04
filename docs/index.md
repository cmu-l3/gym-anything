# Gym-Anything

Gym-Anything is a configurable runtime for wrapping existing software as environments for computer-use agents.

The repository combines:

- a product library in `src/gym_anything/`
- a large benchmark corpus in `benchmarks/cua_world/environments/`
- reference agents and evaluation harnesses in `baselines/`
- remote execution services in `services/`

## Read This First

This repository has multiple supported surfaces with different roles.

- The core runtime is the most stable layer.
- The benchmark corpus is broad and valuable, but task files often contain extra metadata beyond what the core dataclasses load.
- The baseline evaluation scripts are research tools, not a clean public SDK.
- Runner-by-runner behavior differences are part of the supported contract and are documented in [Compatibility Checklist](compatibility.md).

The documentation in this folder is written against the current implementation, not against aspirational behavior.

## Core Concepts

### Environment Construction

Use `gym_anything.make()` or `gym_anything.from_config()` to create a `GymAnythingEnv`.

`from_config()` loads:

- `env.json` or `env.yaml` from an environment directory
- optionally `tasks/<task_id>/task.json` or `task.yaml`
- an optional built-in preset via the environment's `base` field

### Lifecycle

At a high level, a run looks like this:

1. Start a runner.
2. Run environment hooks such as `pre_start` and `post_start`.
3. Run task setup such as `pre_task`.
4. Let the agent interact via GUI actions.
5. Call `step(..., mark_done=True)` to run `post_task` and verification.

### Runners

The current runner implementations are:

- `DockerRunner`
- `QemuApptainerRunner`
- `AVDApptainerRunner`
- `ApptainerDirectRunner`
- `LocalRunner`

### Verification

The main verifier modes currently wired through the dispatcher are:

- `program`
- `image_match`
- `multi`

These are the only verifier modes currently supported by the public runtime contract.

## What To Read Next

- [Getting Started](getting-started.md)
- [API](api.md)
- [Specs](specs.md)
- [Compatibility Checklist](compatibility.md)
- [Runners](runners.md)
- [Tasks & Verifiers](tasks-verifiers.md)
- [Environment Authoring](environment-authoring.md)
- [Distributed Services](distributed-services.md)
- [Current Limitations](current-limitations.md)
