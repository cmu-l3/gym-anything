# Resolve Merge Conflicts Task

**Difficulty**: 🟡 Medium  
**Skills**: Git integration, merge conflict resolution, code comprehension  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Resolve Git merge conflicts in three files using VSCode's integrated merge conflict resolution interface. The repository is in a conflicted state after merging changes from the main branch into a feature branch.

## Context

You just pulled the latest changes from the `main` branch and merged them into your `feature-branch`. Three files now have merge conflicts that must be resolved before you can continue working.

## Files with Conflicts

### 1. `src/config.py`
**Conflict**: Database connection string
- **Current (HEAD/feature-branch)**: Uses `localhost:5432` for local development
- **Incoming (main)**: Uses `db.prod.company.com:5432` for production
- **Required resolution**: Accept the incoming (main) production database URL

### 2. `src/utils/logger.py`
**Conflict**: Log level configuration
- **Current (HEAD/feature-branch)**: Sets log level to `DEBUG`
- **Incoming (main)**: Sets log level to `INFO`
- **Required resolution**: Keep both - use DEBUG in development mode, INFO otherwise (manual merge required)

### 3. `README.md`
**Conflict**: Setup instructions
- **Current (HEAD/feature-branch)**: Docker setup instructions
- **Incoming (main)**: Virtual environment setup instructions
- **Required resolution**: Keep both sets of instructions (both are valid)

## Expected Workflow

1. Open Source Control panel (Ctrl+Shift+G) to see conflicted files
2. Click on each conflicted file to open merge conflict editor
3. For each file, use VSCode's merge conflict UI:
   - `config.py`: Click "Accept Incoming Change" to keep production URL
   - `logger.py`: Click "Accept Both Changes" then manually merge logic
   - `README.md`: Click "Accept Both Changes" to keep both instruction sets
4. Remove any remaining conflict markers manually if needed
5. Save all files (Ctrl+K S to save all)
6. Stage resolved files in Source Control panel (+ icon)
7. Verify no conflict markers remain

## Verification

Checks for:
1. No Git conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) in any file
2. `config.py` contains production database URL (`db.prod.company.com:5432`)
3. `logger.py` contains both DEBUG and INFO log levels
4. `README.md` contains both Docker and virtualenv instructions
5. Python files have valid syntax (no syntax errors)
6. Git repository shows no unmerged files

**Pass Threshold**: 83% (5/6 criteria)