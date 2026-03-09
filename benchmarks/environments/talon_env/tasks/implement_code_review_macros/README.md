# Task: implement_code_review_macros

## Overview

**Difficulty**: very_hard
**Domain**: Software QA / DevOps / Voice Control
**Occupation Context**: QA engineers and senior developers who perform intensive code reviews in GitHub's web interface. RSI-prone roles (reviewers who click through hundreds of diff hunks daily) benefit greatly from hands-free code review macros that automate repetitive navigation patterns.

## Scenario

A QA engineer at a software company reviews 10-15 pull requests per day using GitHub's web interface. The reviewer has chronic repetitive strain injury and uses Talon Voice for all computer interaction. Currently there are no GitHub-specific Talon macros — every code review action requires either typing or clicking. The engineer needs a complete GitHub review macro system.

## Goal

Create two files in `C:\Users\Docker\AppData\Roaming\Talon\user\community\apps\github\`:

### 1. `github_review.talon` — Context-scoped code review commands

- Must have a context header restricting activation to browser windows with GitHub (e.g., `app.name` for Chrome/Firefox + optionally `url` matching github.com)
- Must contain at least 6 voice commands for code review workflows
- A majority of commands must be **multi-step** (have an indented body with multiple action lines)
- Commands must use `sleep()` for at least some timing-sensitive UI interactions
- Example command categories: approve PR, leave inline comment, navigate diff hunks, toggle file tree, request changes, resolve thread

### 2. `github_review.py` — Python actions module

- Must be syntactically valid Python
- Must define at least 4 action methods in an action class (`@mod.action_class`)
- At least 2 methods must use `actions.sleep()` for timing
- Methods should implement real review automation logic

## Why This Is Hard (very_hard)

- Agent must know how to write multi-step Talon commands with indented bodies
- Agent must know how to scope commands to a browser with a specific URL (advanced Talon context)
- Agent must understand `sleep()` usage in Talon for UI timing
- Agent must create both files with correct Talon Python API usage
- No syntax examples or templates are given

## Verification Strategy

| Criterion | Weight | Check |
|-----------|--------|-------|
| `github_review.talon` has browser/GitHub context | 20 pts | `app.name` for browser or `url: /github/` |
| Has >= 6 commands, majority multi-step | 25 pts | Count trigger lines; check for indented bodies |
| Uses `sleep()` in talon command bodies | 10 pts | Regex search for `sleep(` |
| `github_review.py` is valid Python | 15 pts | `ast.parse()` succeeds |
| >= 4 action methods in class | 20 pts | Method count inside `@mod.action_class` |
| >= 2 methods use `actions.sleep()` | 10 pts | `sleep` keyword in method AST |

Pass threshold: 60 points.

## Starting State

- `C:\Users\Docker\AppData\Roaming\Talon\user\community\apps\github\` directory is created and empty
- A sample `.talon` file from community is opened in the editor for syntax reference
- Community apps directory is visible in File Explorer

## Example Commands That Qualify

```talon
# Multi-step command with sleep
approve pull request:
    key(alt-a)
    sleep(500ms)
    insert("Looks good to me!")
    key(ctrl-return)

# Navigation command
next diff hunk: key(n)
previous diff hunk: key(p)

# Toggle command with sleep
toggle file tree:
    key(t)
    sleep(200ms)
```
