# Automate Dev Workflow Task

**Difficulty**: 🟡 Medium  
**Skills**: Task configuration, workflow automation, JSON editing, Command Palette  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Create a VSCode task configuration that automates a repetitive development workflow. The workflow involves installing dependencies, running tests, and starting a development server - operations that developers typically run dozens of times per day.

## Real-World Context

You're working on a Node.js web application and find yourself repeatedly typing the same sequence of terminal commands:
1. `npm install` (install dependencies)
2. `npm test` (run tests)
3. `npm run dev` (start dev server)

Your goal is to automate this using VSCode's Tasks feature so you can run the entire workflow with a single command.

## Expected Workflow

1. Open Command Palette (Ctrl+Shift+P)
2. Type "Tasks: Configure Task" and select it
3. Choose "Create tasks.json from template" or "Open tasks.json file"
4. Create a task configuration that chains the three commands
5. Options:
   - **Compound task**: Create separate tasks for each command and use `dependsOn` to chain them
   - **Shell task**: Create a single shell task that runs all commands sequentially
6. Save the file (Ctrl+S)

## Task Configuration Requirements

The `.vscode/tasks.json` file should:
- Define at least one task with a `label` field
- Include all three operations: npm install, npm test, npm run dev
- Use proper JSON structure with a `tasks` array
- Tasks should be invokable from "Tasks: Run Task" menu

## Example Compound Task Structure
