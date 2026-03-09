# Automate Build Workflow Task

**Difficulty**: 🟡 Medium  
**Skills**: VSCode tasks.json, workflow automation, JSON configuration  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Set up a VSCode Task configuration (`.vscode/tasks.json`) that automates a multi-step build workflow for a Python data processing project. The workflow is currently documented in `BUILD_STEPS.txt` and requires running 4 commands manually.

## Scenario

You're working on a data pipeline project and run the same 4 commands 10-15 times per day:
1. Clean previous outputs
2. Validate input data
3. Process data
4. Create deployment package

Your goal: Automate this entire workflow with a single VSCode task.

## Expected Workflow

1. Read `BUILD_STEPS.txt` to understand the manual workflow
2. Create `.vscode/tasks.json` in the workspace root
3. Define a task that runs all 4 steps in sequence
4. Configure it as the default build task (Ctrl+Shift+B)

## Task Configuration Requirements

Your `tasks.json` should include:
- A task that executes all workflow steps
- Proper command chaining (compound task or shell with `&&`)
- Set as default build task: `"group": {"kind": "build", "isDefault": true}`

## Verification

Checks for:
1. `.vscode/tasks.json` exists and is valid JSON
2. Contains a build/package/workflow task
3. Includes all 4 workflow steps (cleanup, validation, processing, packaging)
4. Configured as default build task
5. Uses appropriate task type (shell or compound)

**Pass Threshold**: All required steps present and properly configured