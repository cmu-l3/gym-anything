# Current Limitations

This page records implementation gaps that matter for users and contributors.

## Spec And Schema Gaps

- `TaskSpec` now preserves common task metadata fields such as `description`, `version`, `name`, and `tags`, but corpus-specific extra keys are still passthrough metadata, not typed runtime behavior.
- Several backend hint fields exist in dataclasses but are still descriptive rather than enforced behavior.
- Validation is minimal. The built-in validator mostly checks structure and optional embedded schemas.
- The raw benchmark corpus is not uniformly verifier-complete. As of March 8, 2026, corpus verification reports `7,277` verified tasks and `385` failed tasks, all due to missing hook asset references.

## Verification Gaps

- The benchmark corpus currently relies almost entirely on program verifiers.

## Compatibility Contract

Runner-by-runner support differences are documented as supported compatibility behavior in [Compatibility Checklist](compatibility.md), not as release blockers.

## API And Behavior Gaps

- `reward_type: "dense"` still depends on task-provided `reward_shaping`; there is no built-in dense reward function.

## Baseline Harness Gaps

- the reference harnesses still expose optional post-reset setup behavior intended for experiment workflows

## Remote-Service Gaps

- the worker supports an explicit `baseline_setup` reset policy for reference-harness workflows, so deployments need to choose between strict `core` parity and baseline-oriented worker-side setup

## Packaging Gaps

- System dependencies are still external to `pip`, but `gym-anything doctor` now checks them explicitly before you run.

## Documentation Policy

These are not historical footnotes. They are current behavioral constraints and should stay documented until the implementation changes.
