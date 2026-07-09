> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# New Environment Onboarding

When you are handed a software environment you have never worked with before, the natural instinct is to immediately start designing tasks. Resist this. Skipping the exploration phase produces tasks that are unverifiable, mis-calibrated, or impossible for agents to attempt. This document gives a systematic protocol for onboarding to any new environment before writing a single task file.

---

## Phase 1: Establish a Stable Baseline

Before doing anything else, confirm the environment itself is reliable.

1. **Launch the app and take a screenshot.** Does it reach a fully usable state? If it shows a loading spinner, first-run wizard, or license dialog, that must be handled in `setup_task.sh` for every task. Document what needs to be dismissed.

2. **Test a cold reset.** Terminate the app and relaunch it. Does it return to the same state, or does it reopen the last session? Apps that reopen the last session require explicit state-clearing in setup scripts.

3. **Look for error states.** If the app crashes, shows a "database not found" message, or fails silently on first launch, document it immediately. These are environment-level bugs to resolve before task creation begins.

If you cannot get a stable, reproducible starting state, stop here and fix the environment before proceeding.

---

## Phase 2: Discover the App's "Scripting Seam"

Every app has some boundary between its internals and the outside world. Finding this boundary determines your entire setup and verification strategy. Work through the following options in order — take the first one that applies.

**Option A: Built-in scripting console or API**
Does the app have a Python console, Lua scripting, macro system, or plugin interface? If yes, this is your primary tool for both seeding state (in `setup_task.sh`) and reading state (in `export_result.sh`). Check the Help menu, the documentation, or look for a "Script" or "Macros" entry in the menu bar.

**Option B: Command-line interface**
Can the app be driven via CLI flags or a separate command-line tool? Run `<appname> --help` or look for a CLI companion tool. Even partial CLI support (e.g., a flag to open a specific file, or a query subcommand) can dramatically simplify setup and verification.

**Option C: Readable data files**
Where does the app store its data? Common locations: the user's home directory, an application-specific config directory (`~/.config/<app>/`, `%AppData%\<app>\`), `/var/lib/`, or `/sdcard/` on Android. Look for SQLite databases (`.db`, `.sqlite`), JSON/XML config files, or flat-file stores. These can often be read and written without involving the app process at all.

**Option D: Export capability**
Can the app export data to a portable format (CSV, JSON, PDF, DICOM, etc.)? Even if you cannot read internal files directly, triggering an export in `export_result.sh` and then parsing the output in `verifier.py` is a fully valid strategy. Document which export formats are available and what data they contain.

**Option E: UI state inspection**
If none of the above apply, you are in pure GUI territory. On Linux, `wmctrl` and `xdotool` can query window titles and UI state. On Android, `uiautomator dump` produces a parseable XML tree. On Windows, `pywinauto` or `pyautogui` can inspect window elements. This is the hardest path — use it only when no other seam exists.

**Document what you find.** Before writing any task, write down which option(s) apply. This choice determines all three files: `setup_task.sh`, `export_result.sh`, and `verifier.py`.

---

## Phase 3: Map Verifiable Actions

Not every action an app can perform is verifiable. Some actions produce no persistent artifact — they only affect the app's in-memory display state, which resets on restart. Before designing tasks, enumerate which actions leave a verifiable trace.

Walk through the app's main menu and feature list. For each significant action, ask:
- Does this action produce a change that persists after the app is closed and reopened?
- Is that change readable via the scripting seam you found in Phase 2?
- Can you tell the *before* and *after* states apart programmatically (not just visually)?

Actions that answer yes to all three are your **verifiable action candidates** — the raw material for tasks. Actions that answer no to any of the three require additional investigation before they can anchor a task.

> **Example:** In a medical imaging viewer, changing the window/level preset changes the display but may not persist to a file. Moving an annotation (fiducial marker) changes an internal data structure that *does* persist. The latter is a verifiable action candidate; the former requires finding how the viewer stores display state before it can be used.

---

## Phase 4: Run a Pilot Trajectory Before Designing the Full Suite

This step is the most commonly skipped and the most consequential.

Before committing to a full set of 5+ tasks for a new environment, run **2–3 abbreviated pilot agent trajectories** (even 10–20 steps each) on the simplest possible task you can imagine. The goal is not to test the task — it is to test whether agents can use the application at all.

**What to look for in pilot trajectories:**

- **Does the agent recognize the app's UI paradigm?** Agents trained on standard desktop apps may struggle with specialized interfaces (3D viewers, graph editors, circuit simulators). If the agent spends all steps staring at the app without clicking anything meaningful, the UI paradigm itself is the obstacle.
- **Does the agent navigate to the right module?** Many apps use module/workspace switching as a primary navigation mechanism. If agents cannot find the target module, every task will fail in the first few steps regardless of difficulty.
- **Does the agent reach the point of action?** The distinction between "agent gets to the right place" and "agent executes the action" matters. If agents reliably reach the right UI context but then fail to commit the action, you have a task design problem (see `11_agent_behavior_patterns.md`). If agents never get close, you have a UI discoverability problem.

**If pilots reveal zero or near-zero success at the simplest possible task:**

Do not design more tasks. Instead, redesign the easiest task using the pre-positioning principle (`11_agent_behavior_patterns.md`) and the tiered difficulty approach from `slicer3d_easy_task_plan.md` as a reference. The starting bar for the environment's easiest task should be: *the correct module is already open, the correct data is already visible, and the agent only needs to perform a single action it can see on screen.*

**Rule of thumb:** If your pilot reveals that agents succeed on the simplest pre-positioned task, you can proceed with designing the full suite. If even the simplest task fails consistently, the environment needs easier entry-point tasks before anything else.

---

## Phase 5: Select a Verification Strategy

Based on what you found in Phases 2 and 3, choose the primary verification strategy for this environment. All tasks in the environment will typically share the same strategy — choosing it upfront prevents inconsistent patterns across your task suite.

| Scripting seam found | Recommended strategy |
|---|---|
| Built-in Python/Lua/script API | Query app state directly via API in `export_result.sh` |
| CLI with query subcommand | Run CLI query commands in `export_result.sh` |
| Server-side DB in Docker (PostgreSQL/MySQL) | `docker exec <db_container> psql/mysql` in `export_result.sh`; write results to `/tmp/<task>_result.json`; copy and parse in `verifier.py`. All three verification scenarios (do-nothing, wrong-target, partial) can be tested offline with mock dicts — see Lesson 38 in `05_learnings_best_practices.md`. |
| HTTP REST API (web apps with API endpoints) | `curl` the app's API in `export_result.sh`; parse JSON responses; write to `/tmp/<task>_result.json`. Prefer over direct DB queries when the app provides a comprehensive API — see Lesson 188 in `05_learnings_best_practices.md`. Can also be combined with direct DB queries for dual-channel verification. |
| SQLite database file | Copy DB out of VM in `verifier.py`, query with `sqlite3` |
| JSON/XML config/data file | Copy file out of VM, parse in `verifier.py` |
| Export to structured format (CSV, JSON) | Trigger export in `export_result.sh`, parse output in `verifier.py` |
| Export to office format (DOCX, XLSX, ODP) | Use ZIP + regex parsing (see Pattern 13 in `03_verification_patterns.md`) |
| GUI state only (no export, no files) | Use UI dump or proxy-based verification (see Pattern 15) |

Document the chosen strategy in the environment-level `README.md` (or equivalent) so that all future task creators for this environment use a consistent approach.

---

## Phase 6: Prepare Starter Files via Selective Stripping

Many applications save state to structured file formats (ZIP+XML, JSON, SQLite, etc.). When you have a complete example file, you can programmatically create starter files by **selectively stripping certain element types while preserving others** — rather than having the agent start from a blank canvas or requiring manual setup.

**The technique**:

1. **Read** the example file using standard libraries (zipfile+XML parser, sqlite3, json).
2. **Identify element types** to strip (the content the agent must create) vs. preserve (the structural scaffold the agent works within).
3. **Remove targeted elements** recursively — including nested children.
4. **Write back** to a new file in the same format.
5. **Record structural baselines** — count every preserved element type for delta computation later (see Pattern 23 in `03_verification_patterns.md`).

**Example element-type decisions by domain**:

| Domain | Strip (agent must create) | Preserve (structural scaffold) |
|--------|--------------------------|-------------------------------|
| Interior design (SH3D, SketchUp) | Furniture, objects | Walls, rooms, floor plan |
| Presentations (ODP, PPTX) | Slide content, images | Slide structure, master template |
| Spreadsheets (ODS, XLSX) | Cell values, charts | Sheet structure, column headers |
| Databases (SQLite) | Data rows | Tables, schema, indexes |
| 3D modeling (VRML, Blender) | Objects, materials | Scene structure, cameras, lights |
| CAD (DXF, DWG) | Entities, blocks | Layers, viewports, dimensions |

**Why this is valuable**:
- Creates realistic starting conditions (a building with walls but no furniture, not a blank void)
- Enables diverse starter files from a single source by varying which elements are stripped
- The preserved structure constrains the agent to work within a realistic context
- Baseline counts enable delta-based verification that only scores agent-created work

**Important**: After stripping, always verify the resulting file still opens correctly in the application — some formats have cross-references that break when elements are removed.

---

## Phase 7: Simplified Verification for File-Based Applications

Many desktop applications store all persistent state in a single structured file (XML, JSON, SQLite, ZIP+XML) rather than a database. When this is the case, two simplifications apply:

### Skip export_result.sh entirely

The standard pipeline is: agent acts -> `export_result.sh` queries state -> writes JSON -> `verifier.py` reads JSON. But when the application's data file IS the output, the verifier can `copy_from_env` the data file directly and parse it. This eliminates `export_result.sh` as a failure point.

**When to use**: The application writes all verifiable state to one or two files on disk (e.g., `.ssrf`, `.ggb`, `.json`, `.conf`). The verifier can parse these formats with standard Python libraries (`xml.etree.ElementTree`, `json`, `sqlite3`, `configparser`).

**When NOT to use**: The application stores state in a running database (MySQL, PostgreSQL), a complex multi-file structure, or the verifier needs state that is only visible through the running application's API.

### Use inline Python heredocs for structured file manipulation in setup_task.sh

For error injection tasks that must modify structured files (XML, JSON, INI configs), embedding Python within bash via heredoc is more reliable than sed/awk/xmlstarlet for complex manipulations:

```bash
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

tree = ET.parse('/path/to/data.xml')
root = tree.getroot()

# Manipulate elements with full Python expressiveness
for elem in root.iter('target_element'):
    elem.set('attribute', 'injected_wrong_value')

tree.write('/path/to/data.xml', xml_declaration=True, encoding='utf-8')
PYEOF
```

**Why this is better than sed/awk**: XML and JSON have nested structure, escaping rules, and encoding requirements that regex-based tools handle poorly. A single unescaped quote or an attribute split across lines will break a sed command silently. Python's built-in parsers handle all of these correctly.

---

## Summary: Before Writing the First Task File

Use this as a gate before starting any task implementation:

- [ ] App launches reliably and reaches a stable usable state
- [ ] Cold reset produces a consistent state
- [ ] First-run dialogs / license screens identified and documented
- [ ] Scripting seam identified (Option A–E above)
- [ ] At least 3 verifiable action candidates identified
- [ ] At least 1 pilot trajectory run on the simplest possible task
- [ ] Pilot result documented: did agent reach the action step? did it commit?
- [ ] Verification strategy selected for the environment

Only after all of these are checked should you proceed to Phase 1 of the task creation checklist (`06_task_creation_checklist.md`).
