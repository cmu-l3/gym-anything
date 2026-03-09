# Task: audit_and_deduplicate_commands

## Overview

**Difficulty**: very_hard
**Domain**: Voice Control Administration
**Occupation Context**: Experienced Talon Voice power users who manage shared community configurations for teams. When multiple contributors add commands, conflicts arise where the same voice trigger appears in multiple files with different actions, causing unpredictable behavior.

## Scenario

A developer manages a shared Talon Voice configuration used by 5 team members. Recently, three team members each added commands to different files without checking for conflicts. Now the configuration has 3 command conflicts — the same voice trigger phrase appears in multiple `.talon` files. When Talon loads conflicting commands, the behavior is undefined and depends on load order. The developer must survey all files, identify the conflicts, resolve them, and write an audit report.

## Goal

The `user_commands/` directory at:
`C:\Users\Docker\AppData\Roaming\Talon\user\community\user_commands\`

Contains three `.talon` files with command conflicts:
- `editor_commands.talon` — OS-wide editor commands (no app restriction)
- `general_commands.talon` — OS-wide general productivity commands
- `productivity_commands.talon` — App-specific commands (scoped to Notepad++)

**Three duplicate voice triggers exist:**
1. `go to line` — in `editor_commands.talon` AND `productivity_commands.talon`
2. `open terminal` — in `editor_commands.talon` AND `productivity_commands.talon`
3. `save file` — in `general_commands.talon` AND `productivity_commands.talon`

**Resolution strategy:** The app-specific (Notepad++ scoped) versions in `productivity_commands.talon` are more specific and should be kept active. The duplicate entries in `editor_commands.talon` and `general_commands.talon` (which are OS-wide with no app restriction) should be commented out or removed.

**After resolving conflicts**, write an audit report to:
`C:\Users\Docker\AppData\Roaming\Talon\user\community\user_commands\audit_report.txt`

The report must reference all 3 conflicts and explain how each was resolved.

## Why This Is Hard (very_hard)

- Agent must survey all `.talon` files in the directory to find conflicts (discovery phase)
- Agent must understand Talon's context scoping to determine which version to keep
- Agent must correctly comment out (not delete) the less-specific duplicate entries
- Agent must not delete any `.talon` files
- Agent must then write a structured audit report
- No instructions are given about which specific triggers conflict

## Verification Strategy

| Criterion | Weight | Check |
|-----------|--------|-------|
| `go to line` duplicate resolved | 20 pts | Active in `productivity_commands.talon` only |
| `open terminal` duplicate resolved | 20 pts | Active in `productivity_commands.talon` only |
| `save file` duplicate resolved | 20 pts | Active in `productivity_commands.talon` only |
| All 3 `.talon` files still present | 15 pts | Files must not be deleted |
| `audit_report.txt` references all 3 conflicts | 25 pts | Text mentions each duplicate trigger |

Pass threshold: 60 points.

## Starting State

Three `.talon` files are created by `setup_task.ps1` with the following conflicts pre-seeded:

| Trigger | `editor_commands.talon` | `general_commands.talon` | `productivity_commands.talon` |
|---------|------------------------|--------------------------|-------------------------------|
| `go to line` | ✓ (OS-wide) | — | ✓ (Notepad++ scoped) |
| `open terminal` | ✓ (OS-wide) | — | ✓ (Notepad++ scoped) |
| `save file` | — | ✓ (OS-wide) | ✓ (Notepad++ scoped) |

`editor_commands.talon` is opened in the editor at task start. The community directory is visible in File Explorer.

## Evidence of Correct Resolution

A correctly resolved `editor_commands.talon` would have:
```talon
# Navigation
# go to line:  <- commented out (less specific)
#     key(ctrl-g)
# Terminal
# open terminal:  <- commented out (less specific)
#     key(ctrl-grave)
```

And `audit_report.txt` would contain text like:
```
Conflict 1: "go to line"
Found in: editor_commands.talon (OS-wide), productivity_commands.talon (Notepad++ scoped)
Resolution: Commented out in editor_commands.talon; kept in productivity_commands.talon
...
```
