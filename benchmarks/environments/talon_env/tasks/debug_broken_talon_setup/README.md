# Task: debug_broken_talon_setup

## Overview

**Difficulty**: very_hard
**Domain**: Assistive Technology / Voice Control Configuration
**Occupation Context**: Software developers relying on Talon Voice for hands-free coding due to repetitive strain injury (RSI). These users maintain complex personal Talon configurations and must diagnose and fix configuration errors without syntax highlighting or IDE assistance.

## Scenario

A software developer who uses Talon Voice for hands-free coding has recently edited several configuration files in their `user_config` directory. After those edits, Talon is no longer recognizing voice commands correctly and the log shows load errors. The developer must identify and fix all configuration errors across four different file types.

## Goal

Fix all configuration errors in the four files inside:
`C:\Users\Docker\AppData\Roaming\Talon\user\community\user_config\`

The four files are:
- `user_settings.talon`
- `window_management.talon`
- `user.browser_shortcuts.talon-list`
- `text_actions.py`

Each file contains exactly one error. Do not delete any file — fix the errors in place and save.

## Why This Is Hard (very_hard)

- The agent receives no hints about what types of errors exist
- Each error is in a different file format (settings, .talon, .talon-list, .py)
- Diagnosing requires reading Talon logs or inspecting each file carefully
- Requires knowing Talon's syntax rules for all four file formats
- No step-by-step guidance is provided

## Verification Strategy

| Criterion | Weight | Check |
|-----------|--------|-------|
| `user_settings.talon` fixed (no quoted numeric) | 25 pts | `speech.timeout` must be a bare number, not `"3"` |
| `window_management.talon` fixed (dash separator) | 25 pts | File must have a line containing only `-` after context header |
| `user.browser_shortcuts.talon-list` fixed (list name) | 25 pts | Header must read `list: user.browser_shortcuts` |
| `text_actions.py` fixed (IndentationError) | 25 pts | File must parse without `SyntaxError` via `ast.parse()` |

Pass threshold: 75 points (3 of 4 bugs fixed).

## Bugs Injected

| File | Bug | Fix |
|------|-----|-----|
| `user_settings.talon` | `speech.timeout = "3"` — quoted string where number required | Change to `speech.timeout = 3` |
| `window_management.talon` | No `-` separator between context header and commands | Add a line with just `-` after the context lines |
| `user.browser_shortcuts.talon-list` | `list: user.web_shortcuts` — name doesn't match filename | Change to `list: user.browser_shortcuts` |
| `text_actions.py` | Extra leading space on one line in `duplicate_line()` body | Remove the extra space |

## Starting State

- All 4 broken files are created in `user_config/` by `setup_task.ps1`
- File Explorer opens to the `user_config/` directory
- Talon is running and will show log errors

## Files Modified by Agent

- `C:\Users\Docker\AppData\Roaming\Talon\user\community\user_config\user_settings.talon`
- `C:\Users\Docker\AppData\Roaming\Talon\user\community\user_config\window_management.talon`
- `C:\Users\Docker\AppData\Roaming\Talon\user\community\user_config\user.browser_shortcuts.talon-list`
- `C:\Users\Docker\AppData\Roaming\Talon\user\community\user_config\text_actions.py`

## Edge Cases

- Agent may fix some but not all bugs → partial score (25 pts each)
- Agent must not delete files (only fix in place)
- Agent must not rename files
