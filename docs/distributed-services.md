# Distributed Services

The repo includes a remote execution stack for running environments behind HTTP services.

It consists of:

- `services/master/app.py`
- `services/worker/app.py`
- `services/dashboard/app.py`
- `RemoteGymEnv` in `src/gym_anything/remote/client.py`

## Roles

### Worker

The worker owns real environment instances.

Current capabilities include endpoints for:

- create
- reset
- step
- close
- capture observation
- file copy helpers
- save/load state
- pause/resume recording

### Master

The master proxies requests across workers and keeps registry state such as:

- worker registration
- health
- load balancing
- environment-to-worker routing

### Dashboard

The dashboard polls servers and provides aggregated monitoring and idle cleanup helpers.

## Remote Client

`RemoteGymEnv` mirrors much of the local interface:

```python
from gym_anything import RemoteGymEnv

env = RemoteGymEnv.from_config(
    remote_url="http://localhost:5000",
    env_dir="benchmarks/cua_world/environments/zotero_env",
    task_id="create_saved_search",
)
```

Supported client methods include:

- `reset`
- `step`
- `close`
- `capture_observation`
- `fetch_path`
- `save_state`
- `load_state`
- `pause_recording`
- `resume_recording`
- `copy_to_env`
- `copy_from_env`

## Important Differences From Local Usage

The remote path is not just a thin transport wrapper.

### Worker Reset Policy

The worker reset endpoint now defaults to the `core` policy, which means:

1. it calls `env.reset(seed=..., use_cache=...)`
2. it forwards `cache_level` and `use_savevm`
3. it does not inject baseline setup behavior

This keeps `RemoteGymEnv.reset()` aligned with local reset behavior by default.

For baseline-harness workflows, the worker also supports an explicit
`baseline_setup` policy that:

1. runs `baselines.evaluation.setup.setup_env(env, steps=50)`
2. disables Ubuntu crash reporting services

You can request that policy through `RemoteGymEnv(..., worker_reset_policy="baseline_setup")`
or by setting `GYM_ANYTHING_WORKER_RESET_POLICY=baseline_setup` on the worker.

### File Copy Caveat

Remote copy methods operate relative to the worker host. A path passed to:

- `copy_to_env`
- `copy_from_env`

must make sense on the worker side.

## Running The Services

### Master

```bash
python -m services.master.app --help
```

### Worker

```bash
python -m services.worker.app --help
```

### Dashboard

```bash
python -m services.dashboard.app --help
```

## When To Use This Stack

Use it when you need:

- multiple worker hosts
- centralized routing
- environment reuse over HTTP
- monitoring of many active environments

Do not use it if you need the smallest possible abstraction surface. For direct library use, prefer local `GymAnythingEnv`.
