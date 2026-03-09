# Automate Full-Stack Development Startup Task

**Difficulty**: 🟡 Medium  
**Skills**: VSCode Tasks, JSON Configuration, Workflow Automation  
**Duration**: 480 seconds  
**Steps**: ~50

## Objective

Create a custom VSCode task configuration that automates the tedious full-stack development startup workflow. Instead of manually running 5+ commands every time you start development, configure VSCode's task system to do it automatically.

## Background

You're a full-stack developer working on a project with:
- Backend Flask server that needs environment variables
- Database migrations that must run before server starts
- Build artifacts that need cleaning
- Multiple terminal commands to remember

The manual workflow is:
1. `bash scripts/clean.sh` - Clean old builds
2. `bash scripts/start_db.sh` - Initialize database
3. `cd backend && APP_ENV=development python server.py` - Start server

This gets tedious fast, especially for new team members!

## Expected Solution

Create `.vscode/tasks.json` with:

1. **Individual tasks**:
   - `clean-dev` - Runs cleanup script
   - `init-database` - Runs database initialization
   - `start-backend` - Starts Flask server with environment variables

2. **Compound task**:
   - `start-dev-environment` - Runs all three tasks in sequence
   - Configured as default build task (so `Ctrl+Shift+B` works)
   - Uses `dependsOrder: "sequence"` for sequential execution

## Verification

Checks for:
1. `.vscode/tasks.json` file exists (20%)
2. Valid JSON structure (20%)
3. All 3 individual tasks present and configured correctly (45%)
4. Compound task with sequential dependencies (15%)
5. Compound task set as default build task (10%)

**Pass Threshold**: 70%

## Tips

- Use Command Palette → "Tasks: Configure Task" to get started
- Task types: "shell" for bash commands
- Use `dependsOn` array for compound tasks
- Set `"dependsOrder": "sequence"` for sequential execution
- Set `"group": {"kind": "build", "isDefault": true}` for default build task