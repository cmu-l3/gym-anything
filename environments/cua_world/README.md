# cua-world

### Overview
- **Environment ID**: `cua-world`
- **Short description**: The CUA-World benchmark (real desktop, web, and mobile applications in full VMs) as a verifiers environment. Each rollout boots a real Linux, Windows, or Android guest; the policy sees screenshots and acts through a `computer` tool; episodes are scored by each task's real programmatic verifier.
- **Tags**: `computer-use`, `gui`, `multi-turn`, `vision`, `tool-use`

### How it works
Each rollout runs gym-anything in-process. With the default `runner="modal"`,
the VM (QEMU with KVM, or the Android emulator) runs inside a Modal VM
Sandbox in the cloud, so nothing is needed locally beyond a Modal token.
Base disk images and checkpoints persist in a Modal Volume, so after the
first boot of an environment, later rollouts load from checkpoint in a few
minutes. The reward is the benchmark's own: the task's `post_task` export
hook runs in the VM and the task's `verifier.py` produces
`{passed, score, feedback}`, mapped to reward exactly as `gym-anything`
does natively (sparse tasks give 0/1, partial/rubric give score/100).

### Prerequisites
1. The gym-anything repo installed into the same interpreter:
   `pip install -e <repo-root>` (provides `gym_anything`, `benchmarks`, and
   the environment folders with tasks and verifiers).
2. This package: `pip install -e <repo-root>/environments/cua_world`.
3. A Modal token (`modal token set ...`) for the default runner.
4. Some environments need a one-time host-side asset fetch
   (`<env>/scripts/fetch_data.sh` or `download_apk.sh`); envs with
   `MANUAL_DOWNLOAD.md` need manually supplied assets.

### Quickstart
```bash
vf-eval cua-world -m google/gemini-3.5-flash \
  -b https://api.pinference.ai/api/v1 -k PRIME_API_KEY \
  -n 1 -r 1 \
  -a '{"env_names": ["gimp_env"], "task_ids": ["horizontal_mirror"], "max_turns": 10}'
```

### Environment Arguments
| Arg | Type | Default | Description |
| --- | ---- | ------- | ----------- |
| `env_names` | str or list | `"gimp_env"` | Benchmark environment folder name(s) |
| `split` | str | `"all"` | Task split (`all`, `train`, `test`, or a named split) |
| `surface` | str | `"raw"` | `"raw"` or `"verified"` task surface |
| `task_ids` | list | None | Optional whitelist of task ids |
| `max_examples` | int | None | Cap dataset rows |
| `runner` | str | `"modal"` | gym-anything runner; `qemu_native`/`docker`/`avd_native` run locally |
| `coordinate_mode` | str | `"norm1000"` | `norm1000` (0-1000 normalized) or `pixel` |
| `max_turns` | int | 15 | Model-turn budget per rollout |
| `keep_recent_screenshots` | int | 3 | Screenshots kept in context; older ones become placeholders |
| `use_cache` | bool | True | Reuse/create gym-anything checkpoints |
| `cache_level` | str | `"post_start"` | Checkpoint level |
| `use_savevm` | bool | False | Full VM-state snapshots (QEMU Linux guests) |

### Metrics
| Metric | Weight | Meaning |
| ------ | ------ | ------- |
| `task_reward` | 1.0 | The benchmark's reward from the real verifier |
| `verifier_passed` | 0.0 | 1.0 if the verifier passed |
| `verifier_score` | 0.0 | Raw verifier score (0-100) |
| `actions_executed` | 0.0 | Low-level actions executed in the VM |
| `parse_errors` | 0.0 | Malformed/missing tool calls |

### Concurrency and cost
One rollout = one VM (one Modal sandbox, ~5 CPU / 12 GB). Set eval
concurrency (`-c`) to the number of simultaneous VMs you are willing to
pay for. First boot of a new environment provisions it (installs the app;
minutes to tens of minutes) and saves a checkpoint to the shared Modal
volume; subsequent rollouts boot from the checkpoint.
