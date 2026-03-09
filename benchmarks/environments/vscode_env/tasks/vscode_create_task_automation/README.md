# Create Custom Build Task for Script Execution

**Difficulty**: 🟡 Medium  
**Skills**: VSCode tasks, workspace configuration, JSON editing, automation  
**Duration**: 300 seconds  
**Steps**: ~80

## Objective

Create a VSCode task configuration in `.vscode/tasks.json` that automates running a Python data analysis script with predefined command-line arguments.

## Scenario

You're working on a sales analysis project with a Python script `analyze_sales.py` that requires multiple command-line arguments. Instead of repeatedly typing the full command, you want to create a VSCode task that runs it automatically.

## Expected Workflow

1. Create `.vscode` directory in the workspace (if it doesn't exist)
2. Create `tasks.json` file inside `.vscode/`
3. Configure a task with:
   - Task label (any descriptive name)
   - Type: `shell`
   - Command: `python`
   - Arguments: `analyze_sales.py --input sales_data.csv --output report.json --verbose`
4. Save the file

## Task Configuration Example

Your `tasks.json` should follow this structure:
