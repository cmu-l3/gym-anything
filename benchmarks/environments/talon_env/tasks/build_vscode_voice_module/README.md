# Task: build_vscode_voice_module

## Overview

**Difficulty**: hard
**Domain**: Developer Tooling / Voice Control
**Occupation Context**: Software developers with RSI who use Talon Voice for hands-free coding in Visual Studio Code. VS Code is the most common editor for Talon users and typically needs a custom module for efficient coding.

## Scenario

A developer using Talon Voice has the community configuration installed but has no VS Code-specific voice module. The community configuration includes hundreds of general commands but nothing VS Code-specific. The developer needs a complete VS Code module — a context-scoped `.talon` file plus a Python actions file — so that VS Code-specific shortcuts fire when VS Code is active but not in other applications.

## Goal

Create two files in `C:\Users\Docker\AppData\Roaming\Talon\user\community\apps\vscode\`:

1. **`vscode.talon`** — context-scoped voice command file that:
   - Has an `app.name` context header restricting commands to VS Code
   - Contains at least 10 voice commands
   - Covers at least 2 distinct command categories (navigation, editing, search, debug, etc.)

2. **`vscode.py`** — Python actions module that:
   - Imports `Module` and/or `Context` from `talon`
   - Defines at least 3 action methods inside an action class
   - Is syntactically valid Python

## Why This Is Hard

- Agent must know Talon file format from scratch (no starter files)
- Agent must know how to write a context-scoped `.talon` file with correct `app.name` header
- Agent must know the Talon Python API (`Module`, `Context`, `@mod.action_class`)
- Agent must create both files with proper structure and syntax
- No template or instructions are given

## Verification Strategy

| Criterion | Weight | Check |
|-----------|--------|-------|
| `vscode.talon` exists with VS Code app context | 20 pts | `app.name` matches VS Code pattern |
| `vscode.talon` has >= 10 voice commands | 25 pts | Count of top-level trigger lines |
| Commands span >= 2 categories | 15 pts | Keyword categories: navigation, editing, search, code |
| `vscode.py` is syntactically valid Python | 20 pts | `ast.parse()` succeeds |
| `vscode.py` defines >= 3 action methods | 20 pts | Method count inside action class |

Pass threshold: 60 points.

## Starting State

- `C:\Users\Docker\AppData\Roaming\Talon\user\community\apps\vscode\` directory is created and empty
- A README_TASK.txt is placed in the target dir for orientation
- A sample .talon file from community is opened in the editor as a syntax reference

## Notes for Verification

The verifier accepts various forms of VS Code context headers:
- `app.name: /Code/`
- `app.name: /Visual Studio Code/`
- `app.name: /vscode/i`
