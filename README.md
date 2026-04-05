# Gym Anything

Gym Anything lets you test AI agents on real software — browsers, IDEs, medical records systems, CAD tools, and more — through a standard environment API.

## Quickstart

```bash
# 1. Install
pip install -e .[all]

# 2. Check what's available on your machine, and help you set up the rest.
gym-anything doctor

# 3. Run an environment interactively
gym-anything run zotero --task create_saved_search -i --open-vnc
```

## Run A Benchmark End To End

Pick an environment, pick a task, pick an agent:

```bash
python -m agents.evaluation.run_single \
  --env_dir benchmarks/cua_world/environments/zotero_env \
  --task create_saved_search \
  --agent ClaudeAgent \
  --agent_args '{"model":"claude-opus-4","exp_name":"demo"}'
```

This starts the Zotero environment, resets it, hands the task to the agent, lets the agent interact with the application through screenshots and mouse/keyboard actions, and runs the automatic checker when the agent finishes.

To run across many tasks at once:

```bash
python -m agents.evaluation.run_batch \
  --agent ClaudeAgent \
  --model claude-opus-4 \
  --split test \
  --max_tasks 10
```

## Three Independent Components

The framework is built around three parts that connect through shared contracts but can each be used or replaced independently:

```
                  ┌──────────────┐
                  │     Core     │
                  └──┬───────┬───┘
                   ▲ │       │ ▲
                   │ ▼       ▼ │
       ┌───────────┴─┐     ┌──┴────────────┐
       │  Benchmarks │◄───►│    Agents     │
       └─────────────┘     └───────────────┘
```

- **Core** (`src/gym_anything/`) — the runtime that starts environments, sends actions, captures observations, and runs verifiers. 
- **Benchmarks** (`benchmarks/cua_world/`) — a ready-made collection of environments and tasks. Each environment wraps a real application; each task defines a specific job, a setup script, and an automatic checker.
- **Agents** (`agents/`) — reference agent implementations (Claude, Gemini, Qwen, Kimi, and others). Bring your own or use ours.

You can use Core alone with your own environments. You can plug any agent into the benchmarks. You can write a new benchmark without touching agent code.



## Contributing

We welcome contributions — new tasks, new environments, bug fixes, and new agent implementations.

The simplest way to contribute is to add a new task to an existing environment. Each task is self-contained in its own folder with a description, a setup script, and a verifier. See the [docs on tasks and checks](https://docs.gym-anything.com/benchmarks/tasks-verifiers) for how these are structured.

If you want to contribute a new environment or agent, start by reading the [contributing guide](https://docs.gym-anything.com/contributing/overview).

## Where To Read Next

- [Installation](https://docs.gym-anything.com/installation) — full setup guide with platform-specific instructions
- [Core Overview](https://docs.gym-anything.com/core/overview) — how the environment API works
- [Benchmarks](https://docs.gym-anything.com/benchmarks/overview) — how environments and tasks are organized
- [Agents](https://docs.gym-anything.com/agents/overview) — reference agents and how to add your own
