# VSCode Merge Conflict Resolution Task (`resolve_merge_conflict@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Git conflict resolution, VSCode Source Control UI, code comprehension, merge decision-making  
**Duration**: 180 seconds  
**Steps**: ~30

## Objective

Resolve Git merge conflicts using VSCode's integrated conflict resolution interface. A merge from `main` into `feature-pricing` has conflicts in two files. The agent must understand both versions, make correct merge decisions, stage the resolved files, and complete the merge.

## Scenario

You're working on a feature branch `feature-pricing`. Meanwhile, a teammate merged changes to `main` that modified the same files you've been editing. When attempting to merge `main` into your branch, Git reports conflicts. Your PR is blocked until you resolve them.

## Expected Workflow

1. Open Source Control panel (Ctrl+Shift+G)
2. Identify conflicted files (marked with `!` or `C`)
3. Click on first conflicted file (`src/utils.py`)
4. Review conflict markers and competing changes
5. Click "Accept Incoming Change" (main branch has new `tax_rate` parameter)
6. Save the file (Ctrl+S)
7. Open second conflicted file (`src/config.py`)
8. Click "Accept Incoming Change" (main branch has better config values)
9. Save the file (Ctrl+S)
10. Stage all resolved files (click `+` or "Stage All Changes")
11. Commit the merge (click checkmark icon)

## Conflict Details

### File 1: `src/utils.py`
- **Current (feature-pricing)**: Added `discount` parameter
- **Incoming (main)**: Added both `discount` AND `tax_rate` parameters
- **Correct resolution**: Accept incoming (has more complete feature)

### File 2: `src/config.py`
- **Current (feature-pricing)**: `TIMEOUT=30`, `RETRIES=3`
- **Incoming (main)**: `TIMEOUT=60`, `RETRIES=5`
- **Correct resolution**: Accept incoming (better production values)

## Verification

Checks for:
1. Merge completed (no `.git/MERGE_HEAD`)
2. Working tree is clean
3. Latest commit is a merge commit (2 parents)
4. No conflict markers remain in files
5. Files have valid Python syntax
6. Resolved code contains expected patterns (`tax_rate` parameter exists)

**Pass Threshold**: 70% (5/7 criteria)