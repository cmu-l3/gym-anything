# cua-world

[![arXiv](https://img.shields.io/badge/arXiv-2604.06126-red.svg?style=for-the-badge)](https://arxiv.org/abs/2604.06126)
[![Docs](https://img.shields.io/badge/Docs-Read-blue?style=for-the-badge&logo=readthedocs&logoColor=white)](https://cmu-l3.github.io/gym-anything/docs/)
[![Interactive Paper](https://img.shields.io/badge/Interactive-Paper-purple?style=for-the-badge)](https://cmu-l3.github.io/gym-anything/interactive_paper.html)
[![GitHub](https://img.shields.io/badge/GitHub-Code-black?style=for-the-badge&logo=github)](https://github.com/cmu-l3/gym-anything)

CUA-World is the benchmark built with
[Gym-Anything](https://github.com/cmu-l3/gym-anything)
([paper](https://arxiv.org/abs/2604.06126)): real desktop, web, and mobile
applications running in full VMs, with the applications selected by their
economic (GDP) impact. Each rollout boots a real Linux, Windows, or Android
guest in the cloud. The policy sees screenshots and acts with mouse and
keyboard, and a checklist-based VLM verifier with task-specific privileged
information scores the trajectory.

## Overview

- **Environment ID**: `cua-world`
- **Scale**: 12,866 tasks across 246 environments (200+ applications, covering all 22 major occupation groups)
- **Platforms**: Linux (206 environments), Windows (29), Android (11)
- **Splits**: `train` (10,397), `test` (2,469), `long_horizon` (201, one long-horizon task per application, often hundreds of steps: CUA-World-Long in the paper)
- **Agent**: a reference agent scaffold (`Qwen3VLAgent`) runs inside the environment; the framework samples your chosen model through it
- **Scoring**: each task's VLM checklist with integrity checks (the paper's verifier); the task's programmatic `verifier.py` optional
- **Runtime**: one VM per rollout (QEMU or Android emulator) inside a Modal sandbox; nothing runs on your machine

Example applications: GIMP, Apache OpenOffice, Ardour, Rocket.Chat, Apache
OFBiz (Linux), Garmin BaseCamp, Epi Info (Windows), QField, Sygic GPS
(Android).

## Install

```bash
prime env install pranjal2041/cua-world
```

## Run

The default configuration runs one GIMP task end to end:

```bash
prime eval run pranjal2041/cua-world -n 1 -r 1
```

Pick the policy with `-m` as usual. Select tasks, applications, or a split
with `-a`:

```bash
prime eval run pranjal2041/cua-world -m google/gemini-3-flash-preview -n 10 -r 1 \
  -a '{"env_names": "all", "split": "long_horizon", "max_turns": 15}'
```

For prime-rl training, reference the environment by id and forward the same
arguments:

```toml
[[orchestrator.train.env]]
id = "cua-world"
args = { env_names = ["gimp_env_all_fast"], split = "train", max_turns = 15 }
```

Because the agent rebuilds a windowed prompt each turn, use
`trajectory_strategy = "branching"` when training.

### Credentials

Two secrets are required (on the hub they live in this environment's Secrets
tab, for local runs export them):

- `GEMINI_API_KEY`: the grader. Every episode is judged by a VLM checklist
  (gemini-3.5-flash by default). Without it, rollouts still run and bill VM
  time but score 0 with an error recorded.
- `MODAL_TOKEN_ID` and `MODAL_TOKEN_SECRET`: the VMs run in Modal sandboxes
  under this account (locally, `modal token set ...` works too).

Running locally with `vf-eval` additionally needs a key for the policy
endpoint, passed with `-b`/`-k`:

```bash
vf-eval cua-world -m gemini-3.5-flash \
  -b https://generativelanguage.googleapis.com/v1beta/openai/ -k GEMINI_API_KEY \
  -n 1 -r 1 -a '{"task_ids": ["add_border"]}'
```

## Environment arguments

The ones most runs touch:

| Argument | Default | Description |
| --- | --- | --- |
| `env_names` | `"gimp_env_all_fast"` | Application environment name(s), or `"all"` |
| `split` | `"all"` | `train`, `test`, `long_horizon`, or `all` |
| `task_ids` | `None` | Optional task allowlist within the selected environments |
| `max_turns` | `15` | Model-turn budget per rollout |
| `agent` | `"Qwen3VLAgent"` | Reference agent scaffold (e.g. `GeminiQwen3Agent` for the gemini-tuned variant) |
| `agent_args` | `{"model": "gemini-3.5-flash", "temperature": 1.0}` | The agent's own arguments |

Advanced (defaults are right for almost everyone):

| Argument | Default | Description |
| --- | --- | --- |
| `verifier_mode` | `"vlm_checklist"` | Set `None` to use each task's programmatic `verifier.py` instead |
| `vlm_model` / `vlm_base_url` / `vlm_api_key_var` | gemini-3.5-flash on Google's endpoint | Change the grader model |
| `runner` | `"modal"` | `qemu_native` / `docker` / `avd_native` run VMs locally instead |
| `remote_url` | `None` | Run rollouts on a gym-anything remote cluster |
| `use_cache` / `cache_level` / `use_savevm` | `True` / `"post_start"` / `False` | VM checkpoint behavior |
| `surface` | `"raw"` | `"raw"` or `"verified"` task surface |
| `seed` / `max_examples` | `0` / `None` | Reset seed, dataset row cap |

## Scoring and metrics

Each task ships a `vlm_checklist.json`: weighted completion items plus
integrity checks, written with privileged information from the task's own
setup (ground truth the agent never sees). The judge scores every item with
pass, partial, or fail. Failing any integrity item zeroes the score,
following the paper.

| Metric | Weight | Meaning |
| --- | --- | --- |
| `task_reward` | 1.0 | Final reward (0 to 1) |
| `verifier_score` | 0.0 | Final checklist score (0-100) after the integrity gate |
| `verifier_completion` | 0.0 | Checklist score (0-100) before the integrity gate |
| `verifier_integrity` | 0.0 | 1.0 if every integrity check passed |
| `verifier_passed` | 0.0 | 1.0 on a perfect, integrity-clean checklist |
| `actions_executed` / `parse_errors` | 0.0 | Actions executed in the VM, malformed tool calls |

Every saved sample carries the full verdict in `info.verifier` (per-item
verdicts with the judge's evidence, sub-scores, overall reasoning) and the
complete multi-turn trajectory (every screenshot and action). Scoring runs
while the VM is still alive. A rollout whose grading fails is recorded with
reward 0 and the error in `info.verifier.error` instead of aborting.

## Cost

One rollout is one VM (about 5 CPU / 12 GB, billed on your Modal account).
Concurrency (`-c`) bounds how many VMs run at once. The first rollout in a
new environment pays a one-time provisioning boot (minutes to tens of
minutes) and saves a checkpoint to a shared Modal volume, after which
rollouts start in a few minutes. A few environments need a one-time asset
fetch (`<env>/scripts/fetch_data.sh`, or `MANUAL_DOWNLOAD.md` for manual
assets) before their tasks pass.

## Reference results

From the paper (test split, Gemini 3 Flash as judge):

| Model | Avg. score | Pass rate |
| --- | ---: | ---: |
| Gemini 3 Flash | 50.1 | 22.6% |
| Kimi-K 2.5 | 37.1 | 12.8% |
| Qwen3-VL-2B | 12.7 | 1.6% |

On `long_horizon` the strongest model reaches 7.5% pass rate at a 500-step
budget, and 27.5% (GPT-5.4) at 2,000 steps.

## How it works

This package is a thin declaration over the gym-anything library. Each
rollout runs the reference agent's `step()` verbatim, and the framework
samples the model through the agent's `llm_call` seam, so prompts, history
handling, and parsing are identical to a local run. Disk images and
checkpoints persist in a Modal volume across rollouts. See the
[hubs documentation](https://cmu-l3.github.io/gym-anything/docs/extras/hubs/)
for the full design.

## Local development

Inside the gym-anything repo, install gym-anything editable first, then this
shell without deps (so it resolves your checkout instead of the pinned tag):

```bash
uv pip install -e ".[modal,prime-rl,benchmark]"      # from repo root
uv pip install -e extras/hubs/prime/cua_world --no-deps
```
