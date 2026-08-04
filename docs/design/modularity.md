# Gym-Anything Modularity — First Principles

## Why the previous designs failed

v1 and v2 were enumerations: lists of extension seams discovered by audit or
by playing scenarios (Isaac's world clock, gameworld's frames, the science
repo's 3-hour step). Every new scenario found the next missing entry, and the
design absorbed it as an "amendment." An enumeration can never be finished —
the fix list was a symptom, not a design. This document replaces the list
with laws that *generate* the answers. A future scenario either follows from
the laws (nothing to do) or exposes a law violation in the code (a bug to
fix) — it is never a design change.

## The model

Gym-Anything has exactly one universal contract, the **episode**:

    reset → (observe → act)* → verify → artifacts

Four **parties** participate in an episode:

| Party   | Role                    | Contract surface                     |
|---------|-------------------------|--------------------------------------|
| world   | the software under test | `BaseRunner`                         |
| policy  | the actor               | `BaseAgent`                          |
| content | envs, tasks, splits     | the benchmark folder shape           |
| judge   | success decision        | verifier callable / checklist        |

**Core is scale infrastructure for episodes** — parallelism, remote
execution, caching protocol, recording, artifact layout, discovery — and
nothing else. Core has no opinion about what a world looks like, how time
passes in it, what an observation contains, or what success means. Every
such opinion belongs to a party.

The boundary of this design: extension happens *within* the episode
contract. Changing the contract itself (new lifecycle phases, cross-episode
structure) is versioned evolution of core — deliberately rare. When it
happens, the laws apply **reflexively to core itself**: new contract fields
are forwarded-not-required (L2 read by core), new abilities are
queried-not-assumed (L4 across versions), so mixed-version fleets — the
normal state of a shared cluster serving several downstream repos — degrade
instead of breaking. Parties are trusted code chosen by the operator;
isolation is a world-implementation concern (runners isolate the software
under test, not the parties).

## The four laws

### L1 — One door, no privileged parties

Every party enters the system through the same mechanism, and the bundled
parties (qemu, cua_world, ClaudeAgent, program verifier) use that same door.
Core orchestration never names a specific party: no runner-name dicts, no
`cua_world` imports, no `agents.agents` special-casing in core code paths.
Per-party facts (capabilities, dependencies, install steps, cache
components, compatibility notes) live **on the party**, and core enumerates
parties, never facts.

References are structural: a path, a resolvable name, or a locator
(`pkg.mod:Name` — already the house idiom). Registration exists only as a
naming convenience (short keys), never as a capability gate, and follows
fail-on-collision semantics because installed order must not decide meaning.

Party names may appear in core as **configuration values** — defaults
(`--benchmark` → `cua_world`), preference orderings — but never as
**control flow** (branches, dicts, or imports keyed on a party). A default
is data: overridable, and absent → an actionable error. Preference itself
is a per-party fact (a runner declares its platform fitness; core sorts),
not a list core maintains.

*Consequence:* anything a bundled party can do, an external party can do —
by construction, not by per-feature effort.

### L2 — Forward, don't interpret

Core interprets only the episode protocol. Everything else is an opaque
payload delivered intact to the party that owns it: observation modalities
core doesn't know, action dicts, spec fields, runner strings on the wire,
create payloads through the master. Core may provide *conveniences* for
common payloads (screenshot capture, wall-clock waits, bash hook wrapping)
— but a convenience is a default the owning party can decline, never a
filter that drops or mangles what core didn't expect.

*Consequence:* a world with joint states, frame sequences, transcripts, or
no screen at all needs zero core changes — core was never allowed to
understand observations in the first place.

### L3 — Context symmetry, state owned by its holder

Every party receives the full episode context, not fragments chosen by
core. The judge already gets this (env_info/task_info with injected
capabilities) — which is why no scenario ever broke the verifier seam. The
policy gets it (`init(task_description, resolution, save_path)`). The world
must too: episode directory, step index, task identity at reset.

Symmetrically, state is *reported by its owner*, never inferred by
observers: a worker doesn't guess env liveness from request timestamps, a
client doesn't guess which task revision a worker has — owners report
(busy refcounts, content digests), infrastructure reads.

*Consequence:* no party is ever blocked because core withheld information
it already had, and no infrastructure kills or corrupts work because it
guessed wrong.

### L4 — Capabilities are queried, absences degrade honestly

Core asks a party what it can do (`supports_*`, doctor status, delivery
acks, save/restore) and adapts: skip the feature, choose the fallback, or
fail with the reason. Capability truth is never a central table, and a
missing capability is never a crash or a silent fake — recording is
skipped, determinism tests skip, savevm is refused with a message.

*Consequence:* heterogeneous fleets and partial-featured worlds are the
normal case, not an error case.

## Enforcement — how the laws stay true

Principles decay without a falsifier. Three permanent mechanisms:

1. **The stranger test.** A synthetic third-party lives in the test suite:
   a toy world with an alien clock and alien modalities (no screen, no
   shell), a toy benchmark folder, a toy agent, a toy verifier — none known
   to core, wired only through the public door. CI runs a full episode
   locally *and through master/worker*. If the stranger passes, any
   downstream passes; every law violation shows up here as a failing test,
   not as a design meeting. This test permanently replaces
   scenario-by-scenario gameplay.
2. **The grep guard.** CI asserts core orchestration modules contain no
   party names in **control flow** — branches, dicts, imports keyed on a
   party. Allowed: bundled party implementation files (the allowlist) and
   declared configuration values per L1 (a default lives in one named
   constant, not scattered through logic). L1 kept honest mechanically.
3. **The dogfood rule.** Any new core feature must be consumed by a bundled
   party through the public mechanism. If qemu needs a side channel, the
   feature is wrong.

## Violation inventory (derived, not designed)

Applying the laws to the current code yields the work list. This is the
*output* of the design, and it is complete exactly insofar as the laws are
— new violations found later are bugs against a law, fixed without
reopening the design.

**L1 violations** — the hand-maintained runner views
(`_runner_for_key`, `_RUNNER_COMPATIBILITY`, `SUPPORTED_RUNNERS`, doctor's
`_RUNNER_DEPS`/probes/`_INSTALL_HINTS`/`_KVM_RUNNERS`,
`installers._PLAN_BUILDERS`, two argparse choices lists,
`infer_runner_key_from_name`, `RUNNER_PROFILES`, `cli._cache_components`,
and the auto-detect / `get_recommended_runner` preference lists — platform
fitness is a per-runner fact, core only sorts);
CLI's `_ENV_SEARCH_PATHS` / `benchmarks.cua_world.registry` import /
verify-corpus default; `getattr(agents.agents, name)` as the only agent
door. → One runner table populated through one door (built-ins, entry
points, locators — dogfooded by built-ins); per-runner facts as
classmethods; `--benchmark` + ambient default resolved by the existing
registry; `--agent` accepts locators.

**L2 violations** — `_capture_observation` drops unknown modalities when a
known one matched; `wait` control sleeps host wall-clock before the world
sees it; `EnvSpec.from_dict` silently drops unknown fields (TaskSpec
already collects `extras`; EnvSpec gains `runner_options` and the same
tolerance); hook commands wrapped in platform-guessed `bash -lc` by core
instead of by the world; remote `env_dir` strings interpreted against the
worker's filesystem (the spec-dict and by-name forms are the compliant
ones; by-name becomes first-class).

**L3 violations** — the world receives no episode context (episode dir,
step, task) while judge and policy do; the worker reaper infers liveness
from `last_activity` with no in-flight tracking (confirmed at
worker.py:333-343 — the root cause of the mid-install reaping incident);
remote identity carries no content truth (worker verifies a task-folder
digest, reported by the owner, instead of trusting path agreement).

**L4 violations** — capability data frozen in `_RUNNER_COMPATIBILITY`
instead of queried (the class-side consolidation resolves this together
with L1); argparse `choices` used as capability validation.

**Packaging (L1 applied to distribution)** — core must not *ship* a
privileged party either: the 79k-file corpus leaves the core distribution
(cua-world published separately, as the hub package precedent already
does); version derives from release tags; a doctor check warns when cwd
shadows installed `agents`/`benchmarks` (the production incident class).

**Deliberate non-changes** — verifier modes stay closed (`mode: program` +
locator already gives judges full generality through the door that exists);
`multi_agent` stays minimal (dynamic populations are world-interpreted
payloads under L2; whole-episode orchestration already has the
`autonomous` policy door).

## Phasing — by falsifier, not by list

1. **Phase 1:** the stranger passes a full local episode. (Forces: one
   door, locator resolution, modality forwarding, context passing,
   `runner_options`, capability queries, `--benchmark`/`--agent`.)
2. **Phase 2:** the stranger passes through master/worker, plus the grep
   guard in CI. (Forces: by-name create with owner-reported digest, opaque
   payload transport, busy-tracked lifecycle, advertising through the
   table.)
3. **Phase 3:** the stranger passes against a core install with no bundled
   corpus. (Forces: the distribution split and version hygiene.)

Each phase is done when its test passes — not when a checklist is empty.
