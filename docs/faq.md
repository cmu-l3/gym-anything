# FAQ

## Which runner should I use?

Use:

- Docker for the simplest Linux local workflow
- QEMU/Apptainer for VM-style isolation, Windows, or HPC-style setups
- AVD for official Android emulator workflows
- Local only for smoke tests

See [Runners](runners.md).

## Why does `pip install -e .` not seem sufficient?

It is sufficient for the Python runtime package now.

You still need system dependencies for the backend you choose, such as Docker, Apptainer, QEMU, Android emulator support, and host `ffmpeg` for screenshot-to-video assembly on non-Docker runs.

## Why is my task description missing from `env.task_spec`?

It should not be for standard benchmark tasks anymore. `TaskSpec` now preserves top-level `description`.

If a task-specific field is still missing, check `env.task_spec.extras`; unmodeled top-level keys are preserved there until they become first-class runtime fields.

## How do I trigger verification?

Call:

```python
env.step([], mark_done=True)
```

That is the path that runs `post_task` and final verification.

## Why does `close()` not give the result I expect?

`close()` now runs `post_task` and verification before shutdown. Use `mark_done=True` when you want the verifier result immediately in the `step()` return payload instead of only in the episode artifacts.

## Does `llm_rubric` work?

No. It is not part of the current public verifier contract.

## Does continuous recording work on every runner?

Live FFmpeg capture starts only on `DockerRunner`.

On QEMU, AVD, and direct Apptainer runs, `close()` can still build `recording.mp4` from step screenshots when host `ffmpeg` is available.

## Are the baseline scripts the public API?

No. They are useful reference harnesses, but they are not the primary product API.

## Do all security and user fields work across all runners?

No. Some fields are Docker-specific today, and some dataclass fields exist without full enforcement.

## Why does remote reset behave differently from local reset?

It should not by default anymore. `RemoteGymEnv` now requests the worker's `core` reset policy, which keeps remote reset aligned with local reset. The worker still offers an explicit `baseline_setup` policy for reference-harness workflows. See [Distributed Services](distributed-services.md).
