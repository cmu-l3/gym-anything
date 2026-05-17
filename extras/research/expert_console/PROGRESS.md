# Expert Console — Build Progress

A running log of the build for `extras/research/expert_console/`. Every milestone
is appended here as it lands, with screenshots once the UI is up.

## What this is

A single-user web app that lets a domain expert nudge the existing
`creation_audit` and `propose_and_amplify` pipelines without ever editing files
directly. The expert inspects curated env/task views, sends a short message,
and the **same** existing pipeline picks up the nudge through a dedicated
`expert_feedback.md` memory file.

See `../expert_console/README.md` for usage and architecture once stage 0 lands.

## Rules of engagement

1. **No fallbacks.** Every failure raises with a clear message. No silent
   degradation, no "skip X if broken" flags.
2. **Reuse, not reimplement.** The dispatcher subprocesses the existing
   `creation_audit/method.py` and `propose_and_amplify/method.py` drivers —
   it does not re-author their logic.
3. **No fake estimates.** Progress is real (current phase, tailing log). No
   invented time-remaining numbers.
4. **Domain-expert friendly.** Scripts and JSON are summarized via GPT-5.4
   (reasoning effort medium) by default. Raw is on expand.

## Approved TODOs

These are the only placeholders allowed in v1:

- `Push to GitHub / Discord` button (top-right) — UI present, action stubbed.
- Auto-checks panel inside task inspection — layout reserved, content TBD.

Everything else must be implemented fully and tested before being checked off.

## Milestones

- [x] **Stage 0 — Scaffolding.** Directory layout, README, this progress doc.
- [x] **Stage 1 — Expert memory wiring.** Dedicated `expert_feedback.md` files
      under both pipelines' memory folders. Existing prompts updated to read them.
- [x] **Stage 2 — Backend foundation.** FastAPI app, SQLite, models, db init.
- [x] **Stage 3 — Inspection service.** Curated env/task views from disk.
- [x] **Stage 4 — Summarization service.** GPT-5.4 reasoning medium with caching.
- [x] **Stage 5 — Memory + diff service.** Read memory, git-diff hunks.
- [x] **Stage 6 — Pipeline dispatch.** Subprocess into existing drivers, SSE
      streaming, stop control.
- [x] **Stage 7 — VNC proxy + env lifecycle.** noVNC over websocket.
- [x] **Stage 8 — REST + SSE API surface.** All endpoints, wired in app.py.
- [x] **Stage 9 — Backend pytest suite.** Per-service tests + TestClient.
- [x] **Stage 10 — Frontend scaffold.** Next.js + Tailwind + shadcn, palette
      matched to the docs site.
- [x] **Stage 11 — Frontend inspection UI.** Picker, three-tab panel.
- [x] **Stage 12 — Frontend chat + routing + memory-diff panel.** SSE progress.
- [x] **Stage 13 — Frontend VNC integration.** Embedded viewer.
- [x] **Stage 14 — Playwright E2E + visual baselines.** Real screenshots.
- [x] **Stage 15 — `launch/method.py`.** `gym-anything-extras research
      expert_console launch` boots the whole thing.
- [x] **Stage 16 — Final visual walkthrough + polish.**

## Log

### Stage 19 — Six fixes from the second review round

User flagged six issues after using the live console. Fixed all.

**Fix 1 — VNC TypeError `body stream already read`.** `jfetch` was
calling `res.json()` and falling through to `res.text()` on error;
fetch only lets you consume the body once. Refactored to read text
first then `JSON.parse(text)`. Verified live: clicked Start on
`odoo_hr_env` — zero page errors, env actually booted via AVFRunner.

**Fix 2 — Stale frontend bundle.** `_frontend_needs_build` now also
returns True when any source file under `frontend/{app,components,lib}`
or top-level config files is newer than `.next/BUILD_ID`. No more
"I edited a component but the launcher serves yesterday's bundle"
trap. Touching `Console.tsx` flips it to True; not touching keeps it
False (verified).

**Fix 3 — Past Creations click does nothing.** Sidebar now invokes a
single `handleSelectSession(id)`:

  * sets `sessionId` on the store
  * restores `selection.envDir` / `selection.taskId` from the row
  * invalidates `env-diff`, `memory-diff`, `memory` queries so the
    side panel refreshes immediately

Also rewrote `InteractionHistory` to drop the broken `useSession`
dead-code path and unify on a single effective session id
(explicit `sessionId` → fallback to most recent active session for
the picked env+task → none).

**Fix 4 — `SHARED MEMORY · ODOO_HR_ENV` claimed "no env-specific notes
yet" when there were notes.** `_looks_env_specific` only inspected
file *names*. Memory tree has shards at
`env_creation_notes/specific_env_notes/<env_dir>/notes.md` — those
match by *parent directory*, not file name. Rewrote the classifier
to walk parents first, then try file-name patterns with `_env`-suffix
normalization (so `openemr_notes.md` correctly maps to
`openemr_env`). Two new tests cover both paths.

**Fix 5 — Summarization needs to lead with data details.** Refined
`_SYSTEM_PROMPT` plus all per-kind prompts to make data the headline:

  * SCRIPT prompt: must call out data sources (URLs, dataset names),
    seeded scale (record counts, file sizes), and flag synthetic /
    placeholder data explicitly.
  * DATA prompt: must give what / source / scale / real-or-synthetic
    in four explicit lines.
  * ENV_SPEC, TASK_SPEC: must mention data fixtures and whether
    references look real vs demo.
  * SYSTEM rule: "If the artifact references data, the data is the
    headline of the summary."

Also enabled the Summarize button on data + evidence files (was
locked behind `disableSummary`); image kinds remain raw-only since
text summarization isn't useful for binaries.

**Fix 6 — "Summarize changes" for completed runs.** New service
`server/services/changes_summary.py` + endpoint
`GET /api/runs/{run_id}/changes-summary`:

  * Pulls the env-scoped git diff (via existing `EnvDiffService`).
  * Looks up the originating feedback message and target env from
    the DB.
  * Calls GPT-5.4 (reasoning effort medium) with a prompt that
    forces a `addressed_feedback` verdict (yes / partial / no /
    unclear) plus a one-line reason and 3-6 substantive bullets.
  * Cached by `(run_id, diff_signature, model, effort)` — re-opening
    a finished run is free.
  * Short-circuits with `addressed=no` when the env diff is empty
    (skips the model entirely).

UI: `RunMonitor` grows a "Changes Summary" footer section on
terminal status (skipped for `stopped` runs). "Summarize changes"
button kicks off the call; result renders with a coloured verdict
chip, file count, +/- totals, plain-English paragraph, verdict
reasoning, and bullets. Refresh button bypasses cache.

**Tests:** +9 (8 changes_summary + 1 env-notes subdir matcher). Full
backend sweep: **114 passed**. E2E unchanged: **8 passed**. Combined:
122 passed.

```
$ pytest extras/research/expert_console/tests --timeout=60
... 122 passed in 36s
```

Screenshots:
| # | State |
|---|---|
| v4_01 | VNC pane idle for odoo_hr_env — Start button visible |
| v4_02 | VNC pane "Booting environment — first boots take time" while AVF VM boots — no crash |

---

### Stage 18 — Routing fix + env diffs + header redesign

User trace of an Odoo HR feedback round revealed three real bugs +
a UX miss. Fixed all.

**Fix 1 — Pipeline routing for "edit existing target" was wrong.**
`env + task picked` was dispatching `propose_and_amplify --stage propose`,
but the proposer's prompt only *creates* 5 new tasks — there's no
edit-in-place mode in it. So an expert nudge "fix the demo data in
promotion_and_department_update" produced 5 unrelated brand-new tasks
and left the original task untouched.

Built two new drivers, narrowly scoped:

- `extras/research/task_generation/propose_and_amplify/pipeline/edit_task.py`
  — refactors **one existing task** in place. Hard constraint in the
  prompt: "you MUST edit files inside this task folder; do NOT create
  new task folders." Validates the task folder exists before
  dispatching. Wired into `propose_and_amplify/method.py` as
  `--stage edit --target-task <name>`.
- `extras/research/software_as_env/creation_audit/edit_env.py` —
  refactors **one existing env** in place (or runs a focused audit
  with `--route audit`). Hard constraint: "do NOT touch task folders;
  this pass is about the env itself." Includes the route-specific
  feedback file reference and refuses to create a new env folder.

New routing matrix (in `DispatchService._build_command`):

| env | task | new_task | route   | driver                                |
|-----|------|----------|---------|---------------------------------------|
| set | set  | False    | n/a     | `edit_task`                           |
| set | —    | True     | n/a     | `propose_and_amplify --stage all`     |
| set | —    | False    | creator | `edit_env --route creator`            |
| set | —    | False    | audit   | `edit_env --route audit`              |
| —   | —    | —        | —       | memory append only                    |

**Fix 2 — Header format auto-injected task names and dropped env names.**

Old: `## <ts> — GLOBAL — promotion_and_department_update — <summary>`

New:
- env picked + scope=specific  → `## <ts> — odoo_hr_env`
- env picked + scope=general   → `## <ts> — odoo_hr_env — global`
- no env picked                → `## <ts> — GLOBAL`

Task names are **never** auto-injected — the dispatcher uses `task_id`
to route to `edit_task`, but the memory entry stays clean. Env names
are **always** shown when an env was picked, even if scope is general,
so a reader can see what triggered the note. The `summary=` arg is
gone from `append_expert_entry`; anchors are derived from the body's
first line.

**Fix 3 — Env / task changes had no UI visibility.**

`MemoryDiffService` only watched memory roots. So when a pipeline
wrote 5 new task folders or modified `scripts/install.sh`, the side
panel showed nothing. Added:

- `EnvDiffService` in `server/services/memory_diff.py` (shares the
  same `_diff_over_paths` engine as `MemoryDiffService` — no
  reimplementation).
- `GET /api/memory/diff/env?env_dir=…` endpoint; 404 on unknown env.
- Frontend: renamed panel to **"Pending Changes"** with two
  sub-sections — **Memory** and **Environment · <env_dir>** — both
  refreshed every 5s. Hunk-level `+/-` totals shown in each section
  header.

**Fix 4 — Default memory_tier=specific when env is picked.**

`ChatComposer` now mirrors `selection.envDir` onto the default memory
tier (specific if env picked, general otherwise) on every change, but
only until the user manually toggles the chip. That manual toggle is
sticky — we don't surprise the expert by flipping their choice
mid-session.

**Tests:** +6 (env diff service + API + new header tests). Full
sweep: **113 passed** (105 backend + 8 E2E) in 36.21s.

Polish screenshots:

| # | State |
|---|---|
| v2_01 | Polished initial render — sidebar with active session |
| v2_02 | Env picked — composer Memory chip auto-defaults to Specific |
| v2_03 | Pending Changes panel — Memory section with real git diffs |
| v2_05 | Pending Changes panel scrolled — Environment · moodle_env section |

---

### Stage 17 — Post-review polish

User flagged three half-baked surfaces during review. Fixed all of them
and swept for others.

**Fix 1 — VNC caching dispatch.** The VNC service was unconditionally
calling `env.reset(use_cache=True, cache_level="default")`, which raises
on runners that don't support checkpoint caching (e.g. `AVFRunner` on
Apple Silicon). Replaced with capability dispatch:

```python
runner = getattr(env, "_runner", None)
if runner and runner.supports_checkpoint_caching():
    env.reset(use_cache=True, cache_level="default")
else:
    env.reset()
```

This is not a fallback — it's reading the runner's declared capability
and calling the right shape. Failures during reset now surface a clear
`VNCError` with the full upstream message.

**Fix 2 — Real Settings panel.** Replaced the "Settings will live here"
stub with a fully wired panel:

- New service `server/services/preferences.py` — file-backed singleton
  at `state/preferences.json`. Validates every patch (unknown keys,
  reasoning effort values, numeric ranges). `threading.RLock` so
  re-entrant calls don't deadlock.
- New router `server/api/settings.py` —
  - `GET /api/settings/diagnostics` — read-only runtime info (backend
    host/port, key presence, claude/npm/git paths, env count, memory
    file counts, expert feedback presence).
  - `GET /api/settings/preferences` — current mutable knobs.
  - `PUT /api/settings/preferences` — patch one or more.
  - `POST /api/settings/preferences/reset` — restore defaults.
- `SummarizationService` now reads model/effort/timeout from
  `PreferencesService` on every call so PUTs take effect immediately
  (no restart).
- Frontend `SettingsPanel` — Runtime section (key chips with set/unset,
  bin paths, repo/state/db paths, env count, expert feedback presence)
  + Summarization form (model input, reasoning effort segmented
  control, max tokens, timeout, completion %, integrity threshold,
  Save + Reset).

**Fix 3 — Inspection right slot now real.** Replaced the static
"Quick Reference" placeholder with the live VNC stage (matches the
sketch: VNC viewer always on the right when an env is picked). When
no env is picked, the slot shows an onboarding empty-state + the
short usage guide. The redundant VNC tab in the inspection panel was
removed; inspection now has two tabs (Audit Files + Interaction
History), VNC lives permanently on the right.

**Other polish:**

- DB engine disposal: `init_db` now disposes a cached engine when the
  settings URL has changed (was leaking SQLite connections in tests).
- `PreferencesService` uses `RLock` (caught a deadlock between
  `update()` and `get()` in the new test suite).
- E2E test renamed: `test_vnc_tab_shows_start_affordance` →
  `test_vnc_right_slot_shows_start_affordance`, asserts against the
  persistent right slot rather than a (now-removed) tab.

**Tests:** +14 (`test_settings_api.py`). Full sweep: **106 passed in
31.82s** (99 backend + 7 E2E).

**Approved TODOs still standing** (only these are intentional
placeholders):
1. Top-right "Push to GitHub / Discord" — UI present, action stubbed.
2. Auto-checks panel inside task inspection — layout reserved.

Polish screenshots written to `tests/e2e/baselines/polish_*.png`:

| # | State |
|---|---|
| 01 | Polished initial render |
| 02 | Settings tab — real diagnostics + summarization form |
| 03 | Env selected — VNC viewer permanently on the right (matches sketch) |
| 04 | Memory Diffs panel open over the new 3-column layout |

---

### Stage 16 — Final visual walkthrough + polish

Live launch through `gym-anything-extras research expert_console launch
--no-open` drove a real user flow end-to-end and captured 12 screenshots
into `tests/e2e/baselines/`:

| # | State |
|---|---|
| 01 | Initial render — sidebar + tabs + Quick Reference + composer |
| 02 | Picker open — full env list with task counts |
| 03 | Hover moodle_env — task list populates on the right |
| 04 | Env selected — full inspection panel rendered, sidebar shows session |
| 05 | Scrolled inspection — scripts, install/setup cards |
| 06 | Memory Diffs panel open — pending diffs across 4 files (+139 -1) |
| 07 | VNC tab — Start button affordance with header |
| 08 | Interaction History tab — pre-submit empty state |
| 09 | Feedback typed in composer |
| 10 | After Send — RunMonitor appears with "running" chip |
| 11 | "this will take time" footer — honest progress messaging |
| 12 | Memory Diffs panel reflects the new entry from the submission |

Polish landed:

- `state/.gitignore` ignores the SQLite db, run logs, and summary cache
  so accidental dev mutations don't pollute the repo.
- `frontend/.gitignore` ignores `node_modules`, `.next`, build logs.
- Schema-mismatch detector in `db.init_db` fails loud with a clear
  remediation hint when an older SQLite file is on disk (see Stage 2
  log entry on the v1 cleanup).
- Sandboxed E2E suite — tests never mutate real `expert_feedback.md`
  files, even though the live launcher does (correctly).

Full test sweep:

```
$ pytest extras/research/expert_console/tests -q
... 92 passed in 35.44s
```

Done. The console is ready for an expert to drive.

---

### Stage 15 — `launch/method.py`

The single CLI entry point. Once `node_modules`, `OPENAI_API_KEY`, and
`claude` are present:

```
gym-anything-extras research expert_console launch
```

What `launch/method.py` does:

1. **Validates prerequisites** loudly — `OPENAI_API_KEY` set, `claude`
   on `PATH` (or `CLAUDE_BIN` set), `npm` on `PATH`, frontend
   `node_modules` present, backend + frontend ports free.
2. **Rebuilds the Next.js bundle when the baked backend URL has
   changed.** A `.next/.expert-console-backend` marker records the URL
   used at last build; if it doesn't match the current invocation, we
   re-run `next build`. (Next bakes rewrites at build time.)
3. **Boots `python -m extras.research.expert_console.server.main`**
   with the chosen host/port; waits for `/api/health`.
4. **Boots `next start`** with the chosen host/port and the
   `EXPERT_CONSOLE_BACKEND` env var; waits for the page to respond.
5. **Opens the browser** to the frontend (unless `--no-open`).
6. **Forwards Ctrl+C** to both subprocesses on exit; if either dies
   unexpectedly, the launcher tears down the other and exits non-zero.

Flags: `--backend-host/port`, `--frontend-host/port`, `--no-open`,
`--rebuild` (force `next build`), `--build-only` (build and exit; for
first-time setup or CI).

Verified live:

```
$ OPENAI_API_KEY=... gym-anything-extras research expert_console launch --no-open
[launch] Reusing existing Next.js build (backend=http://127.0.0.1:8765).
[launch] Starting backend on http://127.0.0.1:8765
[launch] Starting frontend on http://127.0.0.1:3456
[launch] Expert Console ready: http://127.0.0.1:3456
$ curl http://127.0.0.1:3456/api/software | head
{"items":[{"env_dir":"abravibe_env",...
```

---

### Stage 14 — Playwright E2E + visual baselines

`tests/e2e/conftest.py`:

- `sandbox_repo` session fixture copies the relevant repo subtree
  (`extras/research/software_as_env`, `extras/research/task_generation`,
  `benchmarks/cua_world/environments/moodle_env`) into a tmp dir,
  initialises it as a git repo, and points the backend at it via
  `EXPERT_CONSOLE_REPO_ROOT`. E2E mutations never touch the real
  memory files.
- `backend_url` boots `python -m extras.research.expert_console.server.main`
  pointing at the sandbox. Captures logs to
  `/tmp/expert_console_backend_e2e.log` so failures show a real cause.
- `frontend_url` rebuilds the Next.js production bundle with the
  freshly-allocated backend URL baked into the rewrites manifest, then
  runs `next start` against a random port. (Next bakes `rewrites()`
  destinations at build time, so a per-session rebuild is mandatory.)
- `page` fixture launches headless Chromium per test, captures
  `pageerror` events.

`tests/e2e/test_flows.py` covers:
1. Initial render — title visible.
2. Picker opens and filters envs.
3. Pick moodle_env → inspection panel renders ENVIRONMENT SPEC + SCRIPTS.
4. Inspect Memory panel shows pending git diff hunks.
5. VNC tab shows "VNC is not running" + Start button when env selected.
6. Submit memory-only feedback → backend appends to expert_feedback.md
   and `/api/sessions` lists the new session.
7. After two submissions, Interaction History tab shows the timeline.

Screenshots written to `tests/e2e/screenshots/` for visual review.
Baseline screenshots from the manual smoke run live in
`tests/e2e/baselines/` for future visual regression.

```
$ pytest extras/research/expert_console/tests -q
... 92 passed in 31.59s
```

---

### Stages 10–13 — Frontend (scaffold, inspection, chat, VNC, memory diff)

Next.js 15 (App Router) + React 19 + TypeScript + Tailwind 3.4 + Radix
primitives (Popover, Tabs) + TanStack Query + a tiny in-house
`zustand`-style store. noVNC embedded for the VNC viewer.

Palette aligned to the docs site (cyan accent #22d3ee, soft purple
#a78bfa, near-black surfaces). Custom fonts: Space Grotesk (display),
Inter (body), JetBrains Mono (mono).

Layout (matches the original wireframe):

```
┌────────────┬─────────────────────────────────────────────────┬──────────────┐
│ Sidebar    │ Top bar (Inspect Memory · Push to GH [TODO])    │ Memory Diffs │
│ (collapse) ├───────────────────┬─────────────────────────────┤ (toggleable) │
│            │ Inspection panel  │ Quick Reference / Run Mon   │              │
│ Current    │  Audit Files      │                             │ Pending diff │
│ Past       │  VNC              │                             │ General mem  │
│ Settings   │  Interaction Hist │                             │ Shared mem   │
│            ├───────────────────┴─────────────────────────────┤              │
│            │ ChatComposer  (Target · top · feedback · chips) │              │
└────────────┴─────────────────────────────────────────────────┴──────────────┘
```

Components:

- `Sidebar` — collapsible drawer with Current/Past/Settings tabs and
  the live session list.
- `SoftwarePicker` — Radix Popover with search, env list (left), and
  task list (right, auto-loaded on hover). "use env" and "+ new task"
  buttons in the task header.
- `InspectionPanel` — three tabs:
  - **Audit Files**: header card (id, description, tags, base/runner/
    task-count), Environment Spec, Scripts, Data Files (+ external
    sources scanned from scripts), Audit Verdict (renders the audit
    snippet from `audits/`), Auto-Check (Coming Soon placeholder),
    Evidence Docs. Each artifact rendered via `ArtifactCard` with
    Summary (GPT-5.4) / Raw toggle.
  - **VNC**: `VNCStage` with Start/Reset/Stop, embedded noVNC viewer
    via Radix-portaled WebSocket connection to `/api/vnc/ws/{id}`.
  - **Interaction History**: vertical timeline interleaving feedbacks
    and runs with status chips.
- `ArtifactCard` — Summarize on demand using `POST /api/summarize`;
  bullets-and-paragraph rendering with raw fallback.
- `ChatComposer` — single composer with the SoftwarePicker chip,
  optional "What task is on your mind?" top input, feedback textarea,
  route toggle (Creator/Audit, hidden for task-level), memory tier
  toggle (General/Specific), "Suggest audit checklist change", and
  Send button. Disables fields that don't apply (task scope hides the
  audit/creator toggle and the checklist suggestion).
- `RunMonitor` — appears after a dispatched feedback. Live `EventSource`
  subscription to `/api/runs/{id}/stream`. Streams stdout lines into a
  scrolling log. Surfaces current phase (real, from agent output, not
  estimated). Stop button.
- `MemoryPanel` — toggleable right side panel. Live `git diff` over the
  memory roots (refetched every 5s). Shows pending diff hunks with
  +/− coloration, plus per-tier listings of general and shared memory
  files (env-scoped).

Frontend builds clean. Production bundle is 143 KB first-load JS,
31.4 KB for the page itself.

Verified visually by driving the running app with Playwright + Chromium
across these flows (screenshots checked in under `tests/e2e/baselines/`):

1. Initial state.
2. Software picker open.
3. moodle_env hovered (task list populates).
4. moodle_env selected (full inspection view).
5. Memory Diffs panel open (real git diffs from Stage 1 expert_feedback wiring).
6. VNC tab — Start / Reset / Stop affordance.
7. Interaction History tab.
8. Feedback typed.

---

### Stage 7 — VNC proxy + env lifecycle

`server/services/vnc.py`:

- `VNCService.start(env_dir)` is single-user: starting a new env
  tears down any previous session first. Returns `VNCSession` with
  host, port, password, and a backend handle.
- `reset(session_id)` resets the env and refreshes the connection
  info. `stop(session_id)` closes and clears the active session.
- `proxy(session_id, websocket)` is the async byte pump. It opens
  TCP to `vnc_host:vnc_port` and gathers two tasks (`ws→tcp`,
  `tcp→ws`); whichever finishes first ends the proxy.
- `GymAnythingVNCProvider` is the production provider — calls
  `gym_anything.from_config(...).reset(use_cache=True, cache_level="default")`
  and reads `SessionInfo.vnc_port`. Fails loud if the env doesn't
  expose VNC (e.g. `vnc.enable=false` in `env.json`).
- `FakeVNCProvider` (tests) accepts a `port_factory` so tests point
  at an in-process echo server.

`server/api/vnc.py`: `POST /api/vnc/start`, `POST /api/vnc/{id}/reset`,
`POST /api/vnc/{id}/stop`, `GET /api/vnc` (current session),
`WS /api/vnc/ws/{id}` (binary subprotocol).

Tests: 7, including a real `EchoServer` that the WS proxy bridges to —
the WebSocket TestClient sends bytes and reads them back. Covers
single-user replacement, reset, stop, and unknown-env failure.

```
$ pytest extras/research/expert_console/tests/backend -q
... 83 passed in 10.72s
```

---

### Stage 6 — Pipeline dispatch

`server/services/dispatch.py`:

- `DispatchService.submit(payload)` is the single entry point. It:
  1. Validates target (env must exist; task must exist; SPECIFIC
     tier requires env_dir).
  2. Picks the right `FeedbackTarget` (creator / audit / proposer).
  3. Appends the entry to the right `expert_feedback.md` via
     `MemoryService` (the file the existing prompts already read).
  4. Inserts a `Feedback` row, ensures a `Session`, and — if `env_dir`
     is set — launches the existing pipeline driver.
- Routing matrix matches the design memory:

  | env | task | new_task | route   | pipeline call |
  |-----|------|----------|---------|---------------|
  | set | —    | False    | creator | `python -m …creation_audit.method` w/ `--start-idx 1 --blind-nudges 1 --audit-rounds 2` |
  | set | —    | False    | audit   | same but `--blind-nudges 0` (audit only) |
  | set | set  | False    | n/a     | `python -m …propose_and_amplify.method --stage propose` |
  | set | —    | True     | n/a     | `python -m …propose_and_amplify.method --stage all` |
  | —   | —    | —        | —       | memory append only, no dispatch |

  Software name is derived from `env.json` description / spec id /
  env_dir slug — never invented.

- Subprocess launched in a new session (`start_new_session=True`);
  pid + pgid captured. `RealSubprocessLauncher` is the production
  path; tests inject `FakeLauncher` that runs a small bash script.
- Streaming: a daemon thread reads stdout line-by-line, persists each
  to `RunLog` and an on-disk log file under `state/runs/<run_id>.log`.
  Phase markers (`=== Phase Name ===`) update `AgentRun.current_phase`
  so the UI can render the current step without inventing time.
- `stop_run(run_id)` sends `SIGTERM` to the pgid. The thread observes
  the process exit and marks the run `STOPPED`.
- Fail-loud: launch failures mark the run `FAILED` with an event log
  entry and raise; the API converts to HTTP 400.

`server/api/feedback.py`: `POST /api/feedback` → submit + dispatch.
`server/api/sessions.py`: `GET /api/sessions[?status=]`,
`GET /api/sessions/{id}`.
`server/api/runs.py`: `GET /api/runs[?session_id=]`,
`GET /api/runs/{id}`, `POST /api/runs/{id}/stop`,
`GET /api/runs/{id}/stream` (SSE — replays existing logs, polls every
250ms, sends a terminal `status` event and closes on finish).

`server/app.py` instantiates a singleton `DispatchService` on
`app.state.dispatcher`; routers pull from there via a `Request`-aware
dependency.

Tests: 16, including a live SSE streaming check that exercises the
real subprocess (a deterministic bash script), the real log persister
thread, the SSE polling loop, and the stop control.

```
$ pytest extras/research/expert_console/tests/backend -q
... 76 passed in 7.61s
```

---

### Stage 5 — Memory + diff service

`server/services/memory.py`:

- `MemoryService.list_memory(env_dir=None)` walks both memory roots
  and classifies each `*.md` into `GENERAL` vs `SPECIFIC` (env-bound
  files like `openemr_notes.md` are `SPECIFIC`).
- `read_file(rel_path)` reads any memory file. Path traversal and
  reading outside the memory roots raise `MemoryError`.
- `append_expert_entry(...)` writes a properly-formatted entry to the
  right `expert_feedback.md` (`creator`, `audit`, or `proposer`).
  Header: `## <ISO> — <env|GLOBAL> [— <task>] — <summary>`. SPECIFIC
  tier requires `env_dir`. Suggested-checklist-change entries get an
  emphasized prefix line so the audit agent treats them as hard items.

`server/services/memory_diff.py`:

- `MemoryDiffService.get_diff(env_dir=None)` shells out to
  `git diff --no-color --patch HEAD --` over the two memory roots,
  parses the unified diff into `FileDiff[]` + `DiffHunk[]`, and
  appends synthetic "added" entries for untracked files (so a
  brand-new shard appears immediately).
- Fail-loud: missing `git` raises `MemoryDiffError`. Filtering by
  `env_dir` keeps expert_feedback / audit files plus env-named shards.

`server/api/memory.py`: `GET /api/memory[?env_dir=]`,
`GET /api/memory/file?rel_path=...`, `GET /api/memory/diff[?env_dir=]`.

Tests: 18, all passing. Uses sandboxed copies of the memory tree +
local `git init` so the real repo is never mutated.

```
$ pytest extras/research/expert_console/tests/backend -q
... 60 passed in 3.90s
```

---

### Stage 4 — Summarization service

`server/services/summarize.py`:

- `SummarizationService` calls OpenAI Responses API with model
  `gpt-5.4` and `reasoning.effort = "medium"`. The backend is
  abstracted behind a `OpenAIBackend` protocol so tests inject a stub.
- 9 prompt templates (one per `SummaryKind`: script, verifier,
  task_spec, env_spec, audit, vlm_checklist, evidence, data, generic).
  System prompt sets the audience as a non-CS domain expert and
  forces a JSON-only response with `summary` + `bullets`.
- `kind_from_artifact(name, role, kind_hint)` maps an inspection
  Artifact to a SummaryKind so the API endpoint doesn't have to.
- Content-hash file cache under `state/summaries/<sha>.json`. Cache
  key incorporates model, reasoning effort, kind, artifact label, and
  content. `force=True` bypasses cache.
- Fail-loud: empty content, malformed JSON, missing `summary`/`bullets`,
  upstream API failures all raise `SummarizationError`. The API
  endpoint converts that to HTTP 502 with the message.
- Handles `````json … ```` ` fences in case the model wraps its reply.

`server/api/summarize.py`: `POST /api/summarize` with body
`{rel_path, artifact_role, kind_hint, force}`. Returns the cached
or fresh summary in the standard envelope.

Tests: 15 (7 kind-mapping parametrized + 8 service/api). All passing.

```
$ pytest extras/research/expert_console/tests/backend -v
... 42 passed in 0.56s
```

---

### Stage 3 — Inspection service

`server/services/inspection.py`:

- `InspectionService` reads env/task artifacts from disk and returns
  structured `EnvView` / `TaskView` / `SoftwareEntry` / `TaskSummary`
  dataclasses with `to_dict()` for the API layer.
- Surfaces env-level artifacts (`env.json`, install + setup scripts,
  README) and the audit report at `audits/audit_<env_dir>.md` when
  present.
- Surfaces task-level artifacts: `task.json`, `setup_task.sh`,
  `export_result.sh`, `verifier.py`, `vlm_checklist.json`,
  `validated_pi.json`, `README.md` — with the matching `role` label.
- Scans env scripts for external URLs and exposes them as
  `external_sources` so the expert can see what data is being pulled.
- Collects data files under `config/` / `data/` / `fixtures/` /
  `datasets/`, and evidence under `evidence_docs/`.
- `get_artifact_content(rel_path)` returns the raw text with a 64 KB
  preview window, plus a `truncated` flag. Path-traversal blocked —
  any rel_path outside the repo root raises `InspectionError`.

`server/api/software.py` exposes the five endpoints
(`GET /api/software`, `GET /api/software/{env}`, `.../tasks`,
`.../tasks/{task}`, `.../artifact?rel_path=...`).

Tests: 17 total against real `moodle_env` / `audit_student_course_access`.

```
$ pytest extras/research/expert_console/tests/backend/test_inspection.py -v
... 17 passed in 0.45s
```

---

### Stage 2 — Backend foundation

- `server/config.py`: `Settings` (pydantic-settings) with all repo paths
  derived from `__file__`. `validate_runtime()` fails loud if
  `OPENAI_API_KEY` is unset, `claude` binary missing, or expert-feedback
  memory files don't exist.
- `server/db.py`: SQLAlchemy engine on SQLite at
  `state/expert_console.sqlite3` with WAL + foreign-keys enabled.
  `init_db`, `session_scope`, `get_db`, `reset_engine_for_tests`.
- `server/models.py`: `Session`, `Feedback`, `AgentRun`, `RunLog` plus
  string enums (`FeedbackRoute`, `MemoryTier`, `Pipeline`, `RunStatus`,
  `SessionStatus`).
- `server/app.py`: FastAPI factory. Lifespan logs startup/shutdown.
  Currently wires `/api/health` and `/api/config`; other routers land
  in subsequent stages.
- `server/main.py`: uvicorn entry point.
- `pyproject.toml`: new `[expert_console]` extra (fastapi, uvicorn,
  sqlalchemy, pydantic-settings, sse-starlette, openai, websockets).
- `tests/backend/conftest.py` + `test_scaffold.py`: 9 tests, all
  passing. Covers settings resolution, fail-loud validation, db
  bootstrap, ORM round-trip, health + config endpoints.

```
$ pytest extras/research/expert_console/tests/backend/test_scaffold.py -v
... 9 passed in 0.18s
```

---

### Stage 1 — Expert memory wiring

Three new files, sourced by the three existing prompts:

| File | Read by |
|---|---|
| `creation_audit/memory/env_creation_notes/expert_feedback.md` | `prompt.md` (env creation) — new Phase 0 forces a read before anything else |
| `creation_audit/memory/audit_expert_feedback.md` | `audit_prompt.md` (audit) — inline "BEFORE applying the standard checklist" block |
| `propose_and_amplify/memory/task_creation_notes/expert_feedback.md` | `00_getting_started.md` (proposer) — new "Mandatory First Step" section. The first proposer prompt already says "Read ALL files in {notes_ref}", so it gets picked up either way. |

Each entry header is `## <ISO timestamp> — <env or GLOBAL> [— <task name>] — <one-line summary>`. The expert console appends entries to these files at submit time, then dispatches the same pipeline.

---

### Stage 0 — Scaffolding

Created the source tree:

```
extras/research/expert_console/
├── PROGRESS.md
├── README.md
├── __init__.py
├── launch/__init__.py
├── server/
│   ├── __init__.py
│   ├── api/__init__.py
│   ├── services/__init__.py
│   └── schemas/__init__.py
├── state/                      # pre-existing
└── tests/
    ├── __init__.py
    └── backend/__init__.py
```

Set the build rules (no fallbacks, reuse pipelines, no fake estimates,
expert-friendly summarization) at the top of this doc.
