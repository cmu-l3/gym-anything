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
gym-anything benchmark zotero --task create_saved_search --agent ClaudeAgent --model claude-opus-4
```

This starts the Zotero environment, resets it, hands the task to the agent, lets the agent interact with the application through screenshots and mouse/keyboard actions, and runs the automatic checker when the agent finishes.

To run across many tasks at once:

```bash
gym-anything benchmark zotero --agent ClaudeAgent --model claude-opus-4 --split test
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

The simplest way to contribute is to add a new task to an existing environment. Each task is self-contained in its own folder with a description, a setup script, and a verifier. See the [docs on tasks and checks](https://cmu-l3.github.io/gym-anything/docs/docs/benchmarks/tasks-verifiers/) for how these are structured.

If you want to contribute a new environment or agent, start by reading the [contributing guide](https://cmu-l3.github.io/gym-anything/docs/docs/contributing/).

## Where To Read Next

- [Installation](https://cmu-l3.github.io/gym-anything/docs/docs/installation/) — full setup guide with platform-specific instructions
- [Core Overview](https://cmu-l3.github.io/gym-anything/docs/docs/core/) — how the environment API works
- [Benchmarks](https://cmu-l3.github.io/gym-anything/docs/docs/benchmarks/) — how environments and tasks are organized
- [Agents](https://cmu-l3.github.io/gym-anything/docs/docs/agents/) — reference agents and how to add your own
