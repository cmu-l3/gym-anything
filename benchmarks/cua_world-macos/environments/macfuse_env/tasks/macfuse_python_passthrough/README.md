# `macfuse_python_passthrough` — Logging FUSE Passthrough in Python

Environment: `macfuse_env@0.1` (macOS, use.computer dev fleet)

## Domain context

A hobbyist macOS developer is debugging a build tool — they want to see
*exactly* which files the tool reads, opens, or writes when it runs. The
classic Unix answer is a userspace FUSE passthrough filesystem: mount a
"shadow" of the source directory at a separate path, route every operation
through Python, and log every call with a timestamp before delegating to
the real filesystem. The developer then points their tool at the mounted
shadow, runs it, and `tail -f`s the access log.

This is a genuinely common hobby/indie-dev pattern. Reference implementations
exist in fusepy's `examples/passthrough.py`. The agent's job is to recreate
it from scratch — install the library, set up the directories, write the
script, and verify it compiles. The filesystem itself does not have to mount
(the macFUSE kext cannot load on this Apple Silicon sandbox), but the
*source code* must be a real, well-structured FUSE implementation.

## Why this is `very_hard`

The description deliberately does **not** spell out commands, function
signatures, or import names. The agent has to:

- Know which Python package to install. `fusepy` is unmaintained and breaks
  on macFUSE 4.x; the working fork is `mfusepy`, but `import mfusepy`
  is wrong — its module is still called `fuse`. An agent that pip-installs
  `fusepy` or imports `mfusepy` directly will fail C1 and C3.
- Know the FUSE Operations API surface — which methods to override, what
  `getattr` is supposed to return (a dict of `st_*` fields), how `read` /
  `write` map to `os.pread` / `os.pwrite` against an open file handle.
- Wire up Python's `logging` module to a file (not stdout) with a sane
  format.
- Use the correct `FUSE(...)` constructor kwargs (`nothreads=True`,
  `foreground=True`) so the mount would actually work if the kext were
  loadable.
- Use `~/Volumes/` for the user-level mount point — `/Volumes/` is root-only
  and macFUSE can't create entries there from userspace on this sandbox.

There is no easy partial-credit path that crosses 70 without doing the
real work.

## Ground truth (live install in dev sandbox, 2026-05)

| Check | Source | Pass condition |
|---|---|---|
| `mfusepy` importable | `python3 -c "from fuse import FUSE, Operations"` | exits 0, prints "ok" |
| Script exists | `test -s ~/Documents/passthrough_fuse.py` | file present, >500 bytes |
| Imports correct symbol | grep `from fuse import` (any of `FUSE`, `Operations`) | match |
| Subclasses `Operations` | regex `class\s+\w+\s*\(\s*.*Operations.*\)` | match |
| Implements >=5 FUSE ops | regex `def (access|getattr|readdir|open|read|write|create|release|flush)\(` | >=5 unique names |
| Logs to `fuse-access.log` | substring `fuse-access.log` in the script body | present |
| `FUSE(...)` call with right flags | substring `FUSE(` AND (`nothreads` OR `foreground`) | both true |
| Syntax check | `python3 -m py_compile passthrough_fuse.py` | exit 0 |
| Source dir present | `test -d ~/Documents/source && ls | wc -l >= 1` | true |

## Scoring (100 pts, pass at 70)

| Criterion | Pts | Notes |
|---|---:|---|
| C1 `mfusepy` installed (importable) | 15 | binary, requires real `pip install` |
| C2 Script exists & non-empty (>500 bytes) | 10 | binary |
| C3 `from fuse import` line present | 10 | binary |
| C4 `PassthroughFS` subclasses `Operations` | 10 | binary, regex |
| C5 At least 5 of {access, getattr, readdir, open, read, write, create, release} | 20 | binary at 5; below 5 = 0 |
| C6 Logging to `~/Documents/fuse-access.log` configured | 10 | binary, substring |
| C7 `FUSE(` call with `nothreads=True` or `foreground=True` | 10 | binary |
| C8 `python3 -m py_compile` passes | 10 | binary |
| C9 `~/Documents/source/` exists with >=1 file | 5 | binary |
| **Total** | **100** | pass at 70 |

### Anti-Pattern 4 safety (partial-credit cap)

All criteria are binary (no partial-credit fractions). The largest single
criterion the agent can complete with no real software work is C2 (10 pts —
create an empty-ish file >500 bytes). 10 ≪ 70. Even C2 + C9 = 15 ≪ 70.
Reaching 70 requires actually installing mfusepy (C1, 15) plus a real
import, a real class declaration, real method bodies, real logging
configuration, a real FUSE call, and a valid syntax tree.

### Anti-Pattern 13 strategy enumeration

| Strategy | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | C9 | Score | Pass? |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | No |
| Create empty file + source dir | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 5 | 5 | No |
| Stub script with imports only (no class, no methods) | 0 | 10 | 10 | 0 | 0 | 0 | 0 | 10 | 5 | 35 | No |
| Stub script + install mfusepy | 15 | 10 | 10 | 0 | 0 | 0 | 0 | 10 | 5 | 50 | No |
| Real script but forgot `pip install` | 0 | 10 | 10 | 10 | 20 | 10 | 10 | 10 | 5 | 85 | Yes |
| Real script + install (proper job) | 15 | 10 | 10 | 10 | 20 | 10 | 10 | 10 | 5 | 100 | Yes |

The "forgot pip install" row is interesting: an agent that writes a
correct script but never installs mfusepy still passes (85). This is
intentional — the script-writing IS the substantive work; the install is
the cheap mechanical step. We don't want to gate pass/fail entirely on
the install completing, because pip can fail for reasons orthogonal to
the agent's understanding (network blips, etc.).

The "stub script + install" row (50) confirms an agent that takes the
easy path of installing the lib but skipping the write does NOT pass.

## Wrong-target rejection

Strict gate: the script must contain at least one of the strings
`from fuse import` or `import fuse` AND a class declaration referencing
`Operations`. Without both, the verifier treats the file as
not-a-FUSE-implementation and zeros C3–C8 (file existence credit C2 still
applies).

## Setup → Export → Verify flow

1. **`setup_task.sh`** (pre_task)
   - Deletes any pre-existing `~/Documents/passthrough_fuse.py`,
     `~/Documents/fuse-access.log`, `~/Documents/source/`,
     `~/Volumes/watched_source/`.
   - Creates `~/Documents/` and `~/Volumes/` (parent dir for the user-level
     mount point) but **not** `~/Volumes/watched_source/` itself — the
     agent has to create it.
   - Records task-start Unix timestamp at
     `/tmp/macfuse_python_passthrough_task_start_timestamp`.
   - Launches Terminal so the agent has a CLI workspace.
   - Best-effort start-state screencap to
     `/tmp/macfuse_python_passthrough_task_start.png`.

2. **Agent action** (max 80 steps, 900 s)
   - Open Terminal (already launched), `pip3 install mfusepy`.
   - Create `~/Documents/source/` and put at least two files in it.
   - Create `~/Volumes/watched_source/`.
   - Write `~/Documents/passthrough_fuse.py` with class, methods, logging,
     `__main__` block.
   - `python3 -m py_compile` for self-verification.

3. **`export_result.sh`** (post_task)
   - End-state screencap.
   - Probes mfusepy importability, script existence + size, syntax check,
     directory states.
   - Analyzes the script via embedded Python heredoc (regex for class
     declaration, count of method defs, substring checks for log path
     and FUSE flags) and emits
     `/tmp/macfuse_python_passthrough_result.json`.

4. **`verifier.py`** (program-mode success)
   - `copy_from_env` pulls the result file to a host-side temp path.
   - Scores each criterion, applies partial-credit caps, returns
     `{score, passed, feedback, subscores}`.

## Notes

- Pre_task convention: `pre_task` launches Terminal, consistent with
  `12_macos_environments.md`'s "pre_task launches the surface app". For
  macFUSE the surface is Terminal (no GUI window for the framework itself).
- The macFUSE *bundle* on disk is necessary for the dylib path
  (`/usr/local/lib/libfuse.dylib`) that mfusepy's ctypes binding loads
  at import time. Without macFUSE installed, `from fuse import FUSE` would
  fail at import — which is why this task only makes sense inside
  `macfuse_env@0.1`.
- The verifier does NOT try to mount the filesystem. The mount would fail
  on this sandbox because the macFUSE kext requires user consent +
  Reduced Security in Recovery (which the use.computer image cannot
  provide). The deliverable is the source code, not a live mount.
