# Task: Save Notion Window Screenshot

**Difficulty:** easy
**Occupation:** Documentation Specialist / Technical Writer

## Domain Context

Documentation writers, support engineers, and product marketers routinely
need to capture window-mode screenshots of desktop applications for help
articles, app-inventory wikis, marketing collateral, and screencast b-roll.
The macOS-native workflow — Cmd+Shift+4 + Space + click, or `screencapture
-w` in Terminal — produces files with rich metadata that downstream tools
(Spotlight, DEVONthink, asset-management systems) rely on to distinguish
real captures from arbitrary image copies.

This task validates that an agent can drive macOS's built-in screen-capture
utility against a running application in the right capture mode (window,
not full display), and that the captured window is actually an application
window (not the menu bar or a tooltip).

## Goal

While the Notion desktop app is running, produce a window-mode screenshot
of the Notion application window, saved as a `.png` to `~/Desktop` or
`~/Documents`. The capture must be made by macOS's `screencapture` utility
(in window mode), and the resulting image must be plausibly the size of
an actual application window (not a thin menu-bar strip).

## How an Agent Can Solve It

Any of these paths works (verified live; see
`evidence_docs/save_notion_window_screenshot/`):

1. **Keyboard shortcut** — press `Cmd+Shift+4`, then press `Space` to
   switch to window-capture mode, then click on the Notion window.
   Default save location is `~/Desktop/Screenshot YYYY-MM-DD at HH.MM.SS.png`.
   ⚠ The multi-step chord can be unreliable in the use.computer sandbox —
   see `specific_env_notes/notion_macos/notes.md`.

2. **Screenshot toolbar** — press `Cmd+Shift+5` to open the macOS
   Screenshot.app toolbar, click "Capture Selected Window", then click the
   Notion window.

3. **Terminal / SSH** — open Terminal via the Dock and run
   `screencapture -w ~/Desktop/notion.png` then click the Notion window.

## Expected Output Files

| Path | Purpose |
|---|---|
| `~/Desktop/Screenshot *.png` *or* `~/Documents/<anything>.png` | The window-mode screenshot the agent captured. |

The verifier searches `~/Desktop` and `~/Documents` for the most recently
modified .png file with mtime > task_start and grades it on the criteria
below.

## Verification Strategy (6 criteria, 100 pts, pass at 75)

| # | Criterion | Pts |
|---|---|---|
| C1 | A fresh .png exists in `~/Desktop` or `~/Documents` (mtime > task_start) | 10 |
| C2 | File starts with PNG magic bytes (89 50 4E 47 0D 0A 1A 0A) | 5 |
| C3 | File size in [30 KB, 8 MB] | 5 |
| C4 | `com.apple.metadata:kMDItemIsScreenCapture` xattr == True (and file is fresh) | 20 |
| C5 | `com.apple.metadata:kMDItemScreenCaptureType` xattr == `"window"` (and file is fresh) | 30 |
| C6 | PNG dimensions plausibly an application window — width ≥ 400 AND height ≥ 300 AND aspect ratio ≤ 5:1 (and file is fresh) | 30 |

**Thresholds are read from `task.json` `metadata`** (`pass_threshold`,
`min_file_bytes`, `max_file_bytes`, `min_width`, `min_height`,
`max_aspect_ratio`, `required_capture_type`) — change the task without
editing the verifier.

**Partial-credit safety (Anti-Pattern 4):** all criteria are binary.

- Max without C5 (capture-type gate): 10+5+5+20+0+30 = **70 < 75**.
- Max without C6 (dimensions gate): 10+5+5+20+30+0 = **70 < 75**.
- Max without both: 10+5+5+20+0+0 = 40 << 75.

Either single gate is decisive — only a fresh window-mode screencap of a
window-shaped region passes.

**Do-nothing invariant:** the verifier returns `score=0, passed=False`
when no .png candidate is found. There is no env-state baseline credit.

## Anti-Gaming Strategy Enumeration

| Strategy | C1 | C2 | C3 | C4 | C5 | C6 | Total | Pass? |
|---|---|---|---|---|---|---|---|---|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | 0 | 0 | No |
| `touch ~/Desktop/foo.png` | 10 | 0 | 0 | 0 | 0 | 0 | 10 | No |
| Copy unrelated PNG (no screencap xattr, real dims) | 10 | 5 | 5 | 0 | 0 | 30 | 50 | No |
| `screencapture -x` (full display, type='display') | 10 | 5 | 5 | 20 | 0 | 30 | 70 | No |
| `screencapture -R<rect>` (region, type='selection') | 10 | 5 | 5 | 20 | 0 | 30 | 70 | No |
| **Menu-bar capture (1920×24, type='window')** | 10 | 5 | 5 | 20 | 30 | 0 | **70** | **No** |
| **Tiny window capture (e.g. 150×80 tooltip, type='window')** | 10 | 5 | 5 | 20 | 30 | 0 | **70** | **No** |
| Stale pre-existing window capture (mtime predates task_start) | 0 | 5 | 5 | 0 | 0 | 0 | 10 | No |
| Window capture, file >8MB (C3 size fails) | 10 | 5 | 0 | 20 | 30 | 30 | 95 | Yes |
| **`screencapture -w` of Notion body (1432×972, type='window')** | 10 | 5 | 5 | 20 | 30 | 30 | **100** | **Yes** |
| **Cmd+Shift+4 + Space + click on Notion body** | 10 | 5 | 5 | 20 | 30 | 30 | **100** | **Yes** |

Validated by `test_verifier_offline.py` (9 scenarios, all pass —
including `MENU_BAR_CAPTURE` and `TINY_WINDOW_CAPTURE`).

## Setup / Export Pipeline

- **setup_task.sh** launches Notion (idempotent), polls `lsappinfo` for
  window registration, then **sweeps** any pre-existing screencap-tagged
  `.png` files from `~/Desktop` and `~/Documents` so the agent can't earn
  credit for a leftover capture. Records `/tmp/save_notion_window_screenshot_task_start`
  (Unix epoch). Also takes a baseline screenshot to
  `/tmp/save_notion_window_screenshot_start.png` for trajectory evidence
  (not graded).

- **export_result.sh** walks `~/Desktop` and `~/Documents` for `*.png`
  files, picks the most recently modified candidate (preferring those with
  `kMDItemScreenCaptureType == "window"` when multiple are fresh), reads
  the screencap xattrs via `xattr -px ...` + `plistlib.loads(...)`,
  parses the PNG IHDR for dimensions, and emits
  `/tmp/save_notion_window_screenshot_result.json` for the verifier to
  consume via `copy_from_env`. Also records `notion_running` for evidence
  (the verifier does not gate on it).

## Live Behavior Notes (macOS / use.computer)

- The xattrs `com.apple.metadata:kMDItemIsScreenCapture` and
  `com.apple.metadata:kMDItemScreenCaptureType` are stored as binary plists
  (`bplist00…`). Read via `xattr -px` (hex output) and decode with
  `plistlib.loads(bytes.fromhex(...))`.
- macOS's screencapture utility records the capture type as one of:
  `"display"` (full screen, `-x` / `-m`), `"window"` (`-w` / `-W` / `-l`
  or Cmd+Shift+4 + Space + click), or `"selection"` (region, `-R` /
  Cmd+Shift+4 + drag).
- The single-step `Cmd+Shift+3` chord (via `keyboard.hotkey("cmd+shift+3")`)
  reliably triggers a full-display screenshot. The multi-step
  `Cmd+Shift+4 + Space + click` workflow is unreliable in the
  use.computer sandbox; SSH-driven `screencapture -w` + mouse click is
  the reliable agent path.
- When the `screencapture -w` + mouse-click pattern lands on top-of-screen
  pixels, macOS will capture the menu bar (a 1920×24 Notion-owned window
  when Notion is frontmost) instead of the Notion application body. C6
  rejects this gaming path. See `specific_env_notes/notion_macos/notes.md`
  for the full investigation.
