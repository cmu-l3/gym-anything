# Examples

## Manual Runtime Loop

```python
from gym_anything import from_config

env = from_config(
    "benchmarks/environments/zotero_env",
    task_id="create_saved_search",
)

obs = env.reset(seed=42, use_cache=False)

actions = [
    {"mouse": {"left_click": [250, 180]}},
    {"keyboard": {"text": "Papers Since 2010"}},
    {"keyboard": {"keys": ["ctrl", "s"]}},
]

obs, reward, done, info = env.step(actions)
obs, reward, done, info = env.step([], mark_done=True)

env.close()
```

## Observation Inspection

```python
obs = env.reset()

screen_path = obs["screen"]["path"]
print(screen_path)

if "ui_tree" in obs:
    print(obs["ui_tree"]["text"][:500])
```

## Dense Reward Task

```python
env = from_config("benchmarks/environments/<env_name>", task_id="<dense_task>")
obs = env.reset()

obs, reward, done, info = env.step([
    {"keyboard": {"text": "hello"}}
])

print(reward)
```

Dense reward only works when the task config actually provides `reward_type: "dense"` and a working `reward_shaping` reference.

## Single Task Reference Agent Run

```bash
python -m baselines.evaluation.run_single \
  --env_dir benchmarks/environments/zotero_env \
  --task create_saved_search \
  --agent ClaudeAgent \
  --agent_args '{"model":"claude-opus-4","exp_name":"demo"}'
```

## Batch Reference Run

```bash
python -m baselines.evaluation.run_batch \
  --env_dir zotero_env \
  --split test \
  --surface verified \
  --agent ClaudeAgent \
  --model claude-opus-4 \
  --exp_name demo_batch
```

`run_batch` accepts either an environment key like `zotero_env` or a filesystem path, and it reads split definitions from `benchmarks/splits/`.

## Remote Environment Example

```python
from gym_anything import RemoteGymEnv

env = RemoteGymEnv.from_config(
    remote_url="http://localhost:5000",
    env_dir="benchmarks/environments/zotero_env",
    task_id="create_saved_search",
)

obs = env.reset(seed=42, use_cache=False)
obs, reward, done, info = env.step([
    {"mouse": {"left_click": [300, 200]}}
])
env.close()
```
