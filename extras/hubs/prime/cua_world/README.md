# cua-world

### Overview
- **Environment ID**: `cua-world`
- **Short description**: The CUA-World benchmark (real desktop, web, and mobile applications in full VMs) as a verifiers environment. Each rollout boots a real Linux, Windows, or Android guest; the policy sees screenshots and acts through a `computer` tool; episodes are scored by each task's real programmatic verifier.
- **Tags**: `computer-use`, `gui`, `multi-turn`, `vision`, `tool-use`

### How it works
This package is a declaration over the gym-anything library: the dataset is
enumerated by `gym_anything.registry` (the benchmark layout contract), the
rollout logic lives in `gym_anything.integrations.verifiers`, and the
`load_environment` surface comes from `gym_anything.integrations.hub`. Each
rollout runs a real reference agent's `step()` verbatim (select it with
`agent`, exactly like `--agent` locally; default `Qwen3VLAgent`) — the
framework does the sampling through the agent's `llm_call` seam, so the
prompts, history handling, and parsing are the agent's own code, identical
to a local run. With the default `runner="modal"`, the
VM (QEMU with KVM, or the Android emulator) runs inside a Modal VM Sandbox in
the cloud, so nothing is needed locally beyond a Modal token. Base disk images
and checkpoints persist in a Modal Volume, so after the first boot of an
environment, later rollouts load from checkpoint in a few minutes. With
`remote_url`, rollouts run on a gym-anything remote cluster (master/worker)
instead. The reward is the benchmark's own: the task's `post_task` export hook
runs in the VM and the task's `verifier.py` produces
`{passed, score, feedback}`, mapped to reward exactly as gym-anything does
natively (sparse tasks give 0/1, partial/rubric give score/100).

### Prerequisites
1. This package. For local development inside the repo, install gym-anything
   editable first, then this shell without deps (so it resolves the already
   installed gym-anything instead of the pinned git tag):
   ```bash
   uv pip install -e ".[modal,prime-rl,benchmark]"      # from repo root
   uv pip install -e extras/hubs/prime/cua_world --no-deps
   ```
   Consumers install it standalone (`prime env install`, or from the wheel),
   which pulls `gym-anything[modal,prime-rl,benchmark]` from the pinned tag.
2. A Modal token (`modal token set ...`) for the default runner.
3. API keys. There are two distinct roles:
   - **Grader**: with this package's defaults every episode is judged by a
     VLM checklist (`verifier_mode="vlm_checklist"`) using gemini-3.5-flash,
     so `GEMINI_API_KEY` must be set even when your policy is not gemini.
     Without it, rollouts still run (and bill Modal time) but scoring fails
     at the end. Change the grader with `vlm_model`, `vlm_base_url`, and
     `vlm_api_key_var`.
   - **Policy**: the key for whatever OpenAI-compatible endpoint serves the
     model under evaluation (the `-b` and `-k` flags), for example
     `PRIME_API_KEY` for Prime inference.
4. Some environments need a one-time host-side asset fetch
   (`<env>/scripts/fetch_data.sh` or `download_apk.sh`); envs with
   `MANUAL_DOWNLOAD.md` need manually supplied assets. Tasks in those
   environments fail for a fresh install until the assets are supplied.

### Quickstart
A single-task validation run (one rollout, one VM):
```bash
export GEMINI_API_KEY=...   # grader key, see Prerequisites
export PRIME_API_KEY=...    # policy endpoint key
vf-eval cua-world -m google/gemini-3.5-flash \
  -b https://api.pinference.ai/api/v1 -k PRIME_API_KEY \
  -n 1 -r 1 \
  -a '{"env_names": ["gimp_env"], "task_ids": ["horizontal_mirror"], "max_turns": 10}'
```

### Evaluating a split (example: long-horizon with gemini)
`split` selects any named split from the benchmark's `splits/` files
(`train`, `test`, `long_horizon`, or `all`). The `long_horizon` split is one
long-horizon task per application, 201 tasks total. Running gemini as the
policy on Google's OpenAI-compatible endpoint means one key covers both the
policy and the grader:
```bash
vf-eval cua-world -m gemini-3.5-flash \
  -b https://generativelanguage.googleapis.com/v1beta/openai/ -k GEMINI_API_KEY \
  -n 10 -r 1 -c 2 \
  -a '{"env_names": "all", "split": "long_horizon", "max_turns": 15}'
```
Start with a small `-n` (it caps the number of tasks). The first rollout in
each new environment pays a one-time provisioning boot (minutes to tens of
minutes) before its checkpoint makes later rollouts fast, and `-c` bounds how
many VMs run (and bill) at once. Narrow `env_names` to a list to stay inside
specific applications.

The default agent scaffold (`Qwen3VLAgent`) is model-agnostic and is what the
recorded gemini baselines used. Add `"agent": "GeminiQwen3Agent"` to the `-a`
JSON to use the gemini-tuned variant of the same loop (screenshots resized to
the display resolution, coordinates scaled from it).

### Environment Arguments
| Arg | Type | Default | Description |
| --- | ---- | ------- | ----------- |
| `env_names` | str or list | `"gimp_env"` | Benchmark environment folder name(s), or `"all"` for every environment |
| `split` | str | `"all"` | Task split (`all`, `train`, `test`, or a named split) |
| `surface` | str | `"raw"` | `"raw"` or `"verified"` task surface |
| `task_ids` | list | None | Optional whitelist of task ids |
| `max_examples` | int | None | Cap dataset rows |
| `seed` | int | 0 | Reset seed carried in each dataset row |
| `runner` | str | `"modal"` | gym-anything runner; `qemu_native`/`docker`/`avd_native` run locally, None auto-selects |
| `remote_url` | str | None | Run on a gym-anything remote cluster instead of in-process (ignores `runner`) |
| `agent` | str | `"Qwen3VLAgent"` | Reference agent class name from `agents/agents/`, exactly like `--agent` locally (e.g. `GeminiQwen3Agent` for the gemini-tuned scaffold) |
| `agent_args` | dict | `{"model": "gemini-3.5-flash", "temperature": 1.0}` | The agent's own args dict, exactly like `--agent_args` |
| `max_turns` | int | 15 | Model-turn budget per rollout |
| `use_cache` | bool | True | Reuse/create gym-anything checkpoints |
| `cache_level` | str | `"post_start"` | Checkpoint level |
| `use_savevm` | bool | False | Full VM-state snapshots (QEMU Linux guests) |
| `verifier_mode` | str | `"vlm_checklist"` | Task success mode. This package defaults to VLM-checklist grading; set None to use each task's own programmatic verifier |
| `vlm_backend` / `vlm_model` / `vlm_base_url` | str | `"local"` / `"gemini-3.5-flash"` / Google's OpenAI endpoint | VLM grader config for `verifier_mode="vlm_checklist"` |
| `vlm_api_key_var` | str | `"GEMINI_API_KEY"` | Env var name holding the VLM grader key (required with the defaults, see Prerequisites) |

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
