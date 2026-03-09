# Wondershare EdrawMax Environment — Interactive Testing Evidence

## Environment Overview
- **Application**: Wondershare EdrawMax v15.0.6 (amd64)
- **Base VM**: ubuntu-gnome-systemd_highres (Ubuntu 22.04, 1920x1080)
- **Installation**: `.deb` package installed via `dpkg -i` in pre_start hook
- **Test date**: 2026-02-19

## Application Install Verification
```
ii  edrawmax  15.0.6  amd64  All-in-one diagramming software.
```
EdrawMax is installed at `/opt/apps/edrawmax/` with symlink at `/usr/local/bin/edrawmax`.
First-run dialogs (Account Login + File Recovery + notification banner) are dismissed
automatically by the `dismiss_edrawmax_dialogs()` function in `task_utils.sh`.

## Checkpoint Performance
- pre_start checkpoint: ~115s to create (installs EdrawMax 518MB deb)
- post_start checkpoint: ~80s to create from pre_start (EdrawMax warm-up launch)
- Loading from post_start checkpoint: **~17 seconds** (desktop + EdrawMax ready)

## Task Trial Restrictions Found

During interactive testing, the following EdrawMax trial restrictions were discovered:
- **File > Export**: ALL export formats (PDF, PNG, JPEG, Word, etc.) show "Buy Now to Export" button
  — completely blocked in the free/trial tier.
- **Print button**: EdrawMax print dialog's Print button does NOT respond to automation
  (VNC click, xdotool, Enter key) — likely Chromium-embedded UI.
- **Solid Background** (Design > Solid Background): Triggers Account Login dialog — gated.
- **Color Themes** (Design > Color dropdown): 12 theme palettes are FREE. Applying a theme
  stores `<ThemeColor Name="Warm">` data in the eddx file's `theme.xml`, which is verifiable.

Based on these findings, the `export_to_pdf` task was replaced with `apply_theme` since
color theme application is free and creates a verifiable change in the saved eddx file.

## Task Start State Screenshots (Clean — Notification Banner Dismissed)

All screenshots taken after the CRITICAL-1 fix: `dismiss_edrawmax_dialogs()` now correctly
dismisses the embedded in-app "temporarily saved files" notification banner via coordinate clicks.

| Task | Screenshot | Description |
|------|------------|-------------|
| create_flowchart | `create_flowchart_start.png` | EdrawMax home screen, 'Create New' card visible, no banner |
| create_org_chart | `create_org_chart_start.png` | EdrawMax home screen, 'Create New' card visible, no banner |
| create_mind_map | `create_mind_map_start.png` | EdrawMax home screen, 'Create New' card visible, no banner |
| add_page_to_diagram | `add_page_to_diagram_start.png` | Labeled flowchart open (Start→Run Test Suite→All Tests Pass?→Deploy to Staging/Fix Failures), no banner |
| apply_theme | `apply_theme_start.png` | Same labeled flowchart open with default colors, no banner |
| Final verify | `final_verification_create_flowchart_start.png` | Post-fix verification: Home screen, no banner |

## Task Verifier Evidence

The `apply_theme` task was tested end-to-end:
1. Applied "Warm" color theme via Design > Color dropdown > Warm (row 3, column 3)
2. Saved as `/home/ga/themed_flowchart.eddx` via Ctrl+Shift+S
3. File saved successfully: **7959 bytes** (original template: 8199 bytes, delta: 240 bytes > 200 threshold)
4. `theme.xml` inspection confirms: `<ThemeColor Name="Warm" ID="126" ...>` applied
5. See `apply_theme_verified.png` for post-application state

## Setup Log Excerpts

Each `taskNN_<name>_setup.log` file contains the complete stdout/stderr of the
`setup_task.sh` for that task, including EdrawMax startup and dialog dismissal output.

Key lines from setup logs (all tasks):
```
Using bundled template from /workspace/data/
EdrawMax process found after Ns
Dismissing EdrawMax startup dialogs...
File Recovery dialog detected - dismissing...
Dialog dismissal complete.
Start state screenshot saved to /tmp/<task>_start.png
=== <task> task setup complete ===
```
