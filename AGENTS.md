# AGENTS.md

Gym Anything wraps real software as
computer-use environments for AI agents. Three pillars, joined by contracts:

- **Core** (`src/gym_anything/`) — runtime, runners, verifiers, remote stack
- **Benchmarks** (`benchmarks/cua_world/`) — environments, tasks, splits
- **Agents** (`agents/`) — reference agent loops (Claude, Gemini, Qwen, Kimi)

Each pillar can be replaced independently. Keep your change inside the pillar
that owns it. `extras/` sits alongside the pillars for adjacent tooling;
`extras/hubs/<provider>/` holds the thin publishable packages that expose
benchmarks to external training hubs (prime-rl/verifiers), built on the
protocol adapters in `src/gym_anything/integrations/` — never on private
core APIs.

## Before you edit

1. Read `docs/content/docs/` for the area you're touching — `contributing/` and
   the relevant pillar. The docs are the source of truth for architecture,
   lifecycle, and task/verifier structure.
2. Read the public entry point, the test that covers it, and one nearby real
   example. Default reading order is in `contributing/index.mdx`.
3. Work on a branch, not `main`.

## Contracts you must not break

- `src/gym_anything/contracts.py` — `SessionInfo`, `RunnerRuntimeInfo`.
- `src/gym_anything/specs.py` — `EnvSpec`, `TaskSpec`, observation/action types.
- `src/gym_anything/__init__.py` — public API (`make`, `GymAnythingEnv`, etc.).
- Task folder shape: `task.json` + a setup script + `verifier.py`. Verifiers
  return `{"passed": bool, "score": int, "feedback": str}`.

If you change any of these, update every caller and every test.

## Testing

Two kinds. Do both.

**Fast** — always, before you finish:

```bash
python -m pytest tests -q
```

Per-area subsets are listed in `docs/content/docs/contributing/testing.mdx`.

**Live** — this is a computer-use library, so watch it work:

```bash
gym-anything run <env> --task <task> -i --open-vnc
```

A passing test suite with a broken VNC session is a broken change. Live test is highly encouraged, although it should be consulted with the user before running.

## Code style

- Keep the diff minimal. Don't fix nearby code, rename unrelated things, or
  add docstrings to code you didn't touch.
- Don't refactor across pillars in the same change.
- Match the conventions of the file you're editing (logging, naming, error
  handling).
- No leftover `breakpoint()`, commented-out blocks, or `print()` debug calls
  in library code.

## Mindset

- No placeholders. No "we'll add it later." No "stub for now." No
  hedge-everything questions like "should I scope this down?" If something
  belongs in the design, ship it fully. If it doesn't, leave it out
  cleanly — not as a half-built artifact with a TODO.
- Propose the proper integration and execute on it. If a real design
  question exists, name it sharply with a recommended answer and move on
  — not options dressed as cowardice.
