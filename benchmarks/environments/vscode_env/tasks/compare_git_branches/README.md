# Compare Git Branches Task

**Difficulty**: 🟡 Medium  
**Skills**: Git integration, branch comparison, diff view navigation, Source Control panel  
**Duration**: 120 seconds  
**Steps**: ~15

## Objective

Use VSCode's Git integration to compare changes in the file `config/database.py` between the `main` branch and the `feature-auth` branch. Open a diff view to visualize the differences side-by-side.

## Scenario

You're reviewing a teammate's authentication feature branch (`feature-auth`) before they merge it into `main`. They've modified database configuration in `config/database.py`, and you need to see exactly what changed to ensure the settings are correct and secure.

## Expected Workflow

1. Open Source Control panel (Ctrl+Shift+G) or click Source Control icon
2. Access branch comparison via:
   - Command Palette (Ctrl+Shift+P) → "Git: Compare References"
   - Click branch name in status bar (bottom-left)
   - Source Control menu (•••) → Branch → Compare References
3. Select branches to compare:
   - Base: `main`
   - Compare: `feature-auth`
4. From the changes list, locate and click `config/database.py`
5. Verify diff view opens showing side-by-side comparison

## Verification

Checks for:
1. Git repository with both branches exists
2. File `config/database.py` differs between branches
3. Evidence of comparison action (window title, file access)
4. Diff-related indicators in VSCode window state

**Pass Threshold**: 70% (multiple criteria with partial credit)