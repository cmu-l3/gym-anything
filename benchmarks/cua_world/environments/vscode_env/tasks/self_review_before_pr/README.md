# Self Review Before PR Task

**Difficulty**: 🟡 Medium  
**Skills**: Git, Source Control, code review, diff viewing, search  
**Duration**: 180 seconds  
**Steps**: ~30

## Objective

Perform a self-review of code changes before creating a pull request. Identify and fix debugging artifacts and code quality issues across multiple files using VSCode's Source Control view.

## Scenario

You've been working on a user authentication feature and made changes across several Python files. Before submitting a pull request to your team, you need to review your changes and clean up any debugging artifacts or quality issues.

## Expected Workflow

1. Open Source Control view (Ctrl+Shift+G) - already open
2. Review changed files in Source Control panel
3. Click on each file to see diff view
4. Identify and fix the following issues:
   - Remove debug print statement from `auth/login.py`
   - Remove or improve vague TODO comment in `auth/user.py`
   - Remove unused `import pdb` from `utils/helpers.py`
   - Delete or unstage the debug test file `tests/test_debug.py`
5. Stage cleaned files for commit

## Files to Review

- `auth/login.py` - Contains debug print statement
- `auth/user.py` - Contains vague TODO comment
- `utils/helpers.py` - Contains unused pdb import
- `tests/test_auth.py` - Legitimate test file (keep)
- `tests/test_debug.py` - Debug file that should not be committed

## Verification

Checks for:
1. Debug print statement removed from auth/login.py
2. TODO comment removed or improved in auth/user.py
3. Unused pdb import removed from utils/helpers.py
4. Debug test file deleted or unstaged

**Pass Threshold**: 75% (3/4 issues fixed)