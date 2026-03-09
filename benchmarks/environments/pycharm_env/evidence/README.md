# PyCharm Environment Evidence Documentation

## Environment Overview

- **Environment**: `pycharm_env@0.1`
- **Task**: `create_flask_app@1`
- **Difficulty**: easy
- **Last Verified**: 2026-02-02

## Task Description

Create a new Python Flask web application project named 'hello_flask' FROM SCRATCH using PyCharm's GUI at `~/PycharmProjects/hello_flask/`.

### Starting State
- PyCharm Welcome screen visible
- NO existing hello_flask project (directory does NOT exist)
- Clean PycharmProjects folder

### Required Steps (via PyCharm GUI only)
1. Create new project using "New Project" button
2. Create app.py using Alt+Insert or File > New
3. Create test_app.py using Alt+Insert or File > New
4. Create requirements.txt using Alt+Insert or File > New
5. Run tests via PyCharm's test runner

### Success Criteria
1. app.py with Flask app, '/' and '/greet/<name>' routes (35 pts)
2. test_app.py with at least 2 pytest tests (25 pts)
3. requirements.txt with Flask dependency (10 pts)
4. All tests pass (30 pts)

## Anti-Cheat Measures (CRITICAL)

The verifier implements multiple layers of anti-cheat protection:

### 1. Trajectory Pattern Analysis
- **File Creation Detection**: Checks for `alt+Insert` (file creation) vs `ctrl+shift+n` (file navigation)
- **Rejection Rule**: If navigation keys are detected WITHOUT file creation keys, trajectory is rejected
- **Purpose**: Prevents agents from navigating to pre-existing files instead of creating new ones

### 2. GUI Click Threshold
- **Minimum**: `MIN_GUI_CLICKS = 5`
- **Rationale**: Creating 3 files via PyCharm GUI requires clicking on menus, dialogs, buttons
- **Failure**: Trajectories with fewer than 5 clicks are rejected

### 3. Typed Character Threshold
- **Minimum**: `MIN_TYPED_CHARACTERS = 300`
- **Rationale**: Creating Flask app from scratch requires typing substantial code (~530 chars)
- **Failure**: Trajectories with insufficient typing are rejected (detects trivial modifications)

### 4. Meaningful Action Count
- **Minimum**: `MIN_MEANINGFUL_STEPS = 20`
- **Filters Out**: Escape key presses, empty actions
- **Counts**: Clicks, types, key presses (non-trivial), scrolls, drags

### 5. File Timestamp Validation
- **Tolerance**: 5 seconds from episode start
- **Checks**: All 3 files must be created during the episode
- **Detects**: Pre-baked solutions from checkpoints

### 6. PyCharm Project Structure (.idea folder)
- **Required**: `.idea` folder must exist with config files
- **Files checked**: `misc.xml`, `modules.xml`, `workspace.xml`, `*.iml`
- **Purpose**: Proves project was opened/created in PyCharm

### 7. Code Content Validation
- **Minimum code chars**: 100 for app.py, 150 for test_app.py (excluding comments)
- **Detects**: Files that are mostly comments with trivial modifications
- **Validates**: Flask import, routes, test functions

## Verifier Rejection Conditions

The verifier will FAIL the task if ANY of these conditions are true:

1. **Navigation-only trajectory**: Uses `ctrl+shift+n` without file creation indicators
2. **Insufficient clicks**: Fewer than 5 GUI clicks
3. **Insufficient typing**: Fewer than 300 characters typed
4. **Insufficient actions**: Fewer than 20 meaningful actions
5. **Pre-existing files**: Files have timestamps before episode start
6. **No .idea folder**: PyCharm project structure missing
7. **Trivial code**: Files contain mostly comments, insufficient actual code
8. **Missing routes**: app.py doesn't have required Flask routes
9. **Insufficient tests**: test_app.py doesn't have 2+ test functions
10. **Tests fail**: pytest doesn't pass

## Task Setup (setup_task.sh)

The setup script ensures clean state:

```bash
# Remove any pre-existing solution
rm -rf /home/ga/PycharmProjects/hello_flask

# Verify cleanup (abort if directory still exists)
if [ -d "/home/ga/PycharmProjects/hello_flask" ]; then
    echo "ABORTING - Pre-baked solution detected!"
    exit 1
fi

# Record episode start time for timestamp validation
echo "$(date +%s)" > /tmp/episode_start_time
```

## Test Results

### Verifier Threshold Tests

All anti-cheat tests pass:

1. **Navigation-only trajectory**: REJECTED (ctrl+shift+n without file creation)
2. **Insufficient clicks trajectory**: REJECTED (1 < 5 clicks required)
3. **Insufficient typing trajectory**: REJECTED (9 < 300 chars required)
4. **Valid trajectory pattern**: PASSES trajectory validation

```
TEST 1: Navigation-only trajectory - REJECTED ✓
TEST 2: Insufficient clicks trajectory - REJECTED ✓
TEST 3: Insufficient typing trajectory - REJECTED ✓
TEST 4: Valid trajectory pattern - PASSES ✓
```

## Scoring Breakdown

| Criterion | Points | Description |
|-----------|--------|-------------|
| app.py structure | 35 | Flask app with routes |
| test_app.py | 25 | 2+ pytest tests |
| requirements.txt | 10 | Flask dependency |
| Tests pass | 30 | All tests pass |
| **Total** | **100** | |

## Key Files

- `verifier.py` - Main verification logic with anti-cheat
- `setup_task.sh` - Ensures clean state before task
- `export_result.sh` - Exports task results for verification
- `task.json` - Task description and configuration
