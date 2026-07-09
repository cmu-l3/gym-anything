# Environment Creation Workflow for gym_anything — macOS targets

You are creating a new **macOS environment** for gym-anything. macOS envs
run on remote Mac sandboxes via the use.computer fleet (not QEMU/Apptainer
like the Linux envs). This prompt is shorter than the Linux one (`prompt.md`)
because it defers to a single comprehensive reference and two working
example envs you should mirror.

---

## Phase 0: REQUIRED reading order (do this FIRST)

Read these files end-to-end, in this order, before writing a single line of
code. Every macOS-specific gotcha that has been encountered so far is in
them. Reading them up front is much cheaper than re-discovering the same
issues.

1. **`extras/research/software_as_env/creation_audit/memory/env_creation_notes/12_macos_environments.md`** —
   complete guide: UseComputerRunner architecture, `/Users/lume/workspace`
   path (macOS root is read-only under SIP), install patterns (DMG → .app,
   DMG → .pkg, brew cask), Rosetta requirement for x86 apps, the pre_task
   convention, AppleScript-over-SSH TCC trap, VNC URL handling, no checkpoint
   caching, the `Enter` ≠ `Return` keyboard gotcha, Cmd+Space (Spotlight)
   doesn't work, Safari is sandboxed (real prefs in `~/Library/Containers/...`).

2. **`extras/research/software_as_env/creation_audit/memory/env_creation_notes/10_cross_cutting_patterns.md`** —
   37 general patterns including #35 (verify-against-user-flow), #36
   (follow-prior-conventions), #37 (probe-before-speculating). Don't skim;
   these are mandatory.

3. **`extras/research/software_as_env/creation_audit/memory/env_creation_notes/06_env_creation_checklist.md`** —
   the per-env checklist. Note its "If macOS app" branch.

4. **`extras/research/software_as_env/creation_audit/memory/env_creation_notes/specific_env_notes/safari/`** —
   per-env notes for the existing Safari env. Reference for prefs handling,
   plist/SQLite verifier paths, real-world quirks.

5. **`extras/research/software_as_env/creation_audit/memory/env_creation_notes/specific_env_notes/google_earth_macos/notes.md`** —
   the other built-out macOS env (Google Earth Pro). Reference for install
   pattern (DMG → .pkg, Rosetta) and per-task evidence shape.

6. **`benchmarks/cua_world-macos/environments/safari_env/`** — the reference
   *implementation*. Read every file (`env.json`, `scripts/install_*.sh`,
   `scripts/setup_*.sh`, `tasks/<task>/task.json`, `setup_task.sh`,
   `export_result.sh`, `verifier.py`, `test_verifier_offline.py`,
   `collect_evidence.py`). Copy the shape; adapt for your target app.

7. **`benchmarks/cua_world-macos/environments/safari_env/evidence_docs/devtools_security_header_audit/README.md`** —
   complete example of what the evidence package should contain (4 flows:
   probe_prefs, do_nothing, wrong_target, happy_path, interactive_pilot).

8. **`extras/research/task_generation/propose_and_amplify/memory/task_creation_notes/`** —
   task-creation principles (real data, ≥3 verification criteria, baseline
   recording, wrong-target rejection, anti-gaming strategy enumeration,
   offline mock tests required). Same standard as Linux envs apply.

---

## Phase 1: Key constraints specific to macOS

After reading the references above, internalize these constraints — they
shape every decision:

- **Runner is `UseComputerRunner`** (not QEMU, not Docker). Set
  `"runner": "use_computer"` and `"base": "macos"` in env.json.
- **Workspace path is `/Users/lume/workspace`**, not `/workspace`. macOS root
  is read-only under SIP. All `mounts[*].target` and hook paths must use
  `/Users/lume/workspace/...`.
- **User is `lume`**, not `ga`. Passwordless sudo is configured. Don't write
  `su - ga -c "..."`.
- **No DISPLAY env var, no xdotool, no scrot.** Use the use.computer SDK's
  `mac.mouse` / `mac.keyboard` / `mac.screenshot` via the runner, or
  `screencapture -x` for command-line shots.
- **`diagnostics: true` is REQUIRED** in env.json or hook logs are silently
  dropped (the `_finalize` log-collection block is gated on this flag).
- **No checkpoint caching.** `UseComputerRunner.supports_checkpoint_caching()`
  returns False. Don't design tasks that assume cached state. Every reset
  runs all hooks from scratch (cold-start cost ~30s sandbox provision +
  whatever your install takes).
- **`pre_task` launches the app** (the existing cua_world convention applies
  unchanged). Agent tasks are operations inside the running app. Smoke tasks
  have `max_steps: 1` and pre_task does the launching; agent no-ops.
- **`Enter` ≠ `Return`** in macOS apps' form-submit contexts. Use `Enter`
  for "submit URL" in Safari address bar etc. Use `Return` for newlines in
  text fields.
- **Cmd+Space (Spotlight) is disabled** in the base-macos sandbox image.
  Launch apps via Dock click (use visual_grounding for coordinates),
  AppleScript `osascript -e 'tell application "X" to activate'`, or
  `open -a X` via exec_ssh.
- **AppleScript that walks the AX tree fails over SSH** (TCC blocks
  `sshd-keygen-wrapper` from Accessibility). Verifiers should use `pgrep`,
  `lsappinfo`, `defaults read`, file/SQLite reads — NOT `osascript ... tell
  System Events`. The use.computer SDK ships an `ax_helper` for the rare
  case you genuinely need AX (see `12_macos_environments.md`).
- **Safari is sandboxed** — its real prefs live in
  `~/Library/Containers/com.apple.Safari/Data/Library/Preferences/`. Some
  prefs (HomePage) propagate from `defaults write com.apple.Safari`; others
  (`IncludeDevelopMenu`, `ShowFavoritesBar`) don't take effect even with
  cfprefsd flush. Don't design Safari tasks that require the Develop menu
  in the menu bar; agents can use `Cmd+Option+I` shortcut or Terminal curl.

---

## Phase 2: Research the target application

Same as Linux. Specifically for macOS:

- Is the app **available as a .pkg installer**, drag-and-drop `.app`,
  brew cask, or Mac App Store download? Each has different install patterns
  (12_macos_environments.md "Installation Patterns" covers all four).
- Is it **x86_64-only**? On Apple Silicon (the use.computer fleet) you'll
  need to install Rosetta 2 in pre_start (`softwareupdate --install-rosetta
  --agree-to-license`).
- Does it **require Gatekeeper bypass**? Use
  `sudo xattr -dr com.apple.quarantine "/Applications/<App>.app"` after
  install.
- What **state files** does the app use? Look in `~/Library/Application Support/<app>/`,
  `~/Library/Preferences/com.<vendor>.<app>.plist`, `~/Library/Caches/<app>/`,
  app-specific paths. These are your verifier's source of truth.
- Does the app **need Mac-only data formats** (DMG, SDEF, plist, sqlite)?
  Use Python's stdlib `plistlib`, `sqlite3`; for binary plist convert with
  `plutil -convert xml1`.

---

## Phase 3: Create the env

Mirror `benchmarks/cua_world-macos/environments/safari_env/`. The minimum
file set:

```
benchmarks/cua_world-macos/environments/<env_name>/
├── env.json                         # base="macos", runner="use_computer",
│                                    # diagnostics=true, mounts at
│                                    # /Users/lume/workspace/{scripts,tasks},
│                                    # hooks pointing at those paths
├── scripts/
│   ├── install_<app>.sh             # pre_start; install via DMG/.pkg/brew cask
│   └── setup_<app>.sh               # post_start; defaults write, mkdir state dirs
└── tasks/
    └── <task_name>/
        ├── task.json                # env_id matches env.json id
        ├── setup_task.sh            # pre_task; launches the app, polls lsappinfo
        ├── export_result.sh         # post_task; flushes WAL, queries state,
        │                            # writes /tmp/<task>_result.json
        ├── verifier.py              # reads result via env_info["copy_from_env"],
        │                            # ≥3 criteria, strict wrong-target gate
        ├── test_verifier_offline.py # required offline mock tests
        └── README.md                # domain context, schema/data ref, edge cases
```

Steps in order:

1. Copy `safari_env/env.json` as a starting point. Change `id`, `description`,
   `tags`, `category`. Keep `base: "macos"`, `diagnostics: true`. Update
   mount source paths to your new env's `scripts/` and `tasks/` dirs.

2. Write `install_<app>.sh`. Use one of the patterns from
   `12_macos_environments.md` "Installation Patterns". Always include
   Rosetta install on Apple Silicon if the app is x86_64. Always strip
   quarantine attributes after install.

3. Write `setup_<app>.sh`. Configure the app's prefs via `defaults write`
   (and `killall cfprefsd` after), pre-create state directories under
   `~/Library/`, do any one-time configuration that's independent of the
   per-task work.

4. Write a smoke task (`tasks/launch_<app>/`) FIRST. `max_steps: 1`,
   pre_task launches the app + polls `lsappinfo` until the window registers,
   verifier checks `pgrep -x <App>` + `lsappinfo list | grep -i <App>`.
   This validates the env install + launch + verifier scaffolding end-to-end
   with zero agent logic.

5. **chmod +x ALL .sh files immediately after creating them.** The
   permissions are silent killers (Lesson #1 in
   `05_learnings_best_practices.md`).

---

## Phase 4: Test interactively

**You MUST test live** before declaring the env done. Use the
`extras/research/software_as_env/creation_audit/macos_session.py` interactive
driver (or build one with the same shape if you need a different signature).
It maintains a persistent use.computer sandbox across multiple CLI calls.

Workflow:

```bash
# Boot — runs install + setup + pre_task hooks
USE_COMPUTER_API_KEY=$USE_COMPUTER_API_KEY \
USE_COMPUTER_BASE_URL=$USE_COMPUTER_BASE_URL \
python3 extras/research/software_as_env/creation_audit/macos_session.py boot

# Iterate: screenshot → visual_grounding → click/type/key → screenshot
python3 .../macos_session.py screenshot /tmp/s.png
python3 .../macos_session.py ground "Where is the URL bar?" /tmp/s.png
python3 .../macos_session.py click 960 75
python3 .../macos_session.py type "https://github.com/"
python3 .../macos_session.py key Enter
python3 .../macos_session.py screenshot /tmp/s2.png
# … etc

# Finalize: runs post_task + verifier, copies all artifacts
python3 .../macos_session.py finalize --out-dir benchmarks/cua_world-macos/environments/<env_name>/evidence_docs/<task_name>/interactive_pilot
python3 .../macos_session.py destroy
```

The `visual-grounding` MCP server is configured at `/Users/pranjal/Developer/gym-anything2/.mcp.json` for
Claude Code. If you're driving the agent via Codex or another CLI, you can
also import `visual_grounding` directly:

```python
from extras.research.software_as_env.creation_audit.mcp.screenshot_query_mcp import visual_grounding
print(visual_grounding("Where is the Save button?", "/tmp/s.png"))
```

**Eyes-on verification is required.** Look at every screenshot yourself
(don't just check that the screenshot file was written). Read every JSON
artifact end-to-end. Confirm the JSON the agent produced contains
plausible domain content (real values, not just keys). See pattern #35 in
`10_cross_cutting_patterns.md`.

---

## Phase 5: Evidence package

Per `task_creation_notes/04_evidence_documentation.md`, the evidence lives at
`benchmarks/cua_world-macos/environments/<env_name>/evidence_docs/<task_name>/`.

Minimum:

- `<task_name>_screenshot.png` — start-state evidence (what an interactive
  viewer sees when reset returns)
- `<task_name>_evidence.json` — structured metadata (timestamps, prefs
  state, baseline counts, what the export script saw, hook logs)

Strongly recommended for macOS tasks specifically:

- Per-flow subdirs (`do_nothing/`, `wrong_target/`, `happy_path/`,
  `interactive_pilot/`) each with their own screenshots + summary.json +
  hook logs. See `safari_env/evidence_docs/devtools_security_header_audit/`
  for the canonical shape.
- The actual agent output file (e.g. the report JSON the agent wrote),
  copied via `copy_from_env` BEFORE the sandbox is destroyed.

---

## Phase 6: Self-audit before declaring done

Before considering the env complete, check:

- [ ] All offline mock tests pass (`test_verifier_offline.py` covers
      do-nothing, wrong-target, partial, full-correct, plus anti-gaming
      scenarios per `task_creation_notes/14_task_design_antipatterns.md`).
- [ ] At least one live run via `macos_session.py` reached `passed=True` for
      a happy-path trajectory.
- [ ] At least one live run via `macos_session.py` returned `passed=False,
      score=0` for the do-nothing trajectory.
- [ ] Strict wrong-target gate fires (Pattern #2 in
      `task_creation_notes/03_verification_patterns.md`).
- [ ] Pass threshold is strictly > sum of partial-only credit
      (`task_creation_notes/14` Anti-Pattern #4).
- [ ] No `setup_task.sh` `echo` / `print()` leaks ground truth (Anti-Pattern
      #10).
- [ ] Evidence directory exists with screenshots + result JSONs.
- [ ] Description matches difficulty per Anti-Pattern #1.

---

## Phase 7: What NOT to do (macOS pitfalls)

- ❌ Don't use `base: "ubuntu-gnome-systemd_highres"`. Use `base: "macos"`.
- ❌ Don't write `/workspace/...`. Use `/Users/lume/workspace/...`.
- ❌ Don't use `su - ga -c` or `DISPLAY=:1`. Hooks run as `lume`, no DISPLAY.
- ❌ Don't use `xdotool`, `wmctrl`, `scrot`. macOS has no X server.
- ❌ Don't open Spotlight via Cmd+Space. It's broken in the sandbox.
- ❌ Don't write `osascript ... tell System Events ...` and expect it to
  work — TCC denies that path over SSH.
- ❌ Don't design tasks that require Safari's Develop menu in the menu bar.
  It can't be reliably enabled.
- ❌ Don't omit `diagnostics: true` — you'll lose hook logs.
- ❌ Don't try to use checkpoint caching — `use_cache=True` will raise.
- ❌ Don't trust `defaults read` after a `defaults write` until you've
  verified the value also appears in the sandboxed container path
  (`~/Library/Containers/com.<vendor>.<app>/Data/Library/Preferences/`).

---

## Final notes

The reference safari_env was built end-to-end with these patterns; if a
question isn't answered above, grep `safari_env/` for the answer before
inventing a new pattern. If you do invent a new pattern, document it under
`specific_env_notes/<your_env>/notes.md` so the next agent doesn't have to
re-discover it.
