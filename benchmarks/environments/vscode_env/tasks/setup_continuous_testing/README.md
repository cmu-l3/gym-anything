# Setup Continuous Testing Task

**Difficulty**: 🟡 Medium  
**Skills**: VSCode configuration, testing workflow, settings management  
**Duration**: 300 seconds  
**Steps**: ~50

## Objective

Configure VSCode to automatically run pytest tests whenever you save a Python file, creating a continuous testing workflow with instant feedback.

## Scenario

You're working on a Python data validation module and want tests to run automatically on every save, so you catch bugs immediately rather than discovering them 10 commits later.

## Expected Workflow

1. Open VSCode Settings (Ctrl+,) or edit settings.json directly
2. Enable pytest as the test framework
3. Enable auto-test discovery on save
4. Configure auto-save for seamless workflow
5. (Optional) Create workspace-specific test settings

## Required Settings

The following settings should be configured in user settings (`/home/ga/.config/Code/User/settings.json`):

- `python.testing.pytestEnabled: true` - Enable pytest
- `python.testing.autoTestDiscoverOnSaveEnabled: true` - Auto-discover tests on save
- `files.autoSave: "afterDelay"` - Enable auto-save
- `python.testing.pytestArgs: ["tests", "-v"]` - Configure pytest arguments

## Verification

Checks for:
1. User settings.json exists and is valid JSON
2. pytest is enabled
3. Auto-test discovery on save is enabled
4. Auto-save is configured
5. (Bonus) Workspace settings configured

**Pass Threshold**: 80% (4/5 points)