# Configure Environment Switcher with Safeguards Task

**Difficulty**: 🟡 Medium  
**Skills**: VSCode tasks, workspace settings, shell/Python scripting, safety automation  
**Duration**: 600 seconds  
**Steps**: ~60

## Objective

Configure a safe, visual environment switching system for a backend service that prevents accidental production operations. Create VSCode tasks, status bar indicators, and a confirmation-protected switching script.

## Scenario

You maintain a backend API service that connects to development, staging, and production databases. Last week, a team member accidentally ran a migration against production while thinking they were in dev mode. You need to implement a fool-proof switching system with visual indicators and safeguards.

## Expected Implementation

### 1. VSCode Tasks (`.vscode/tasks.json`)
Create three tasks that invoke the switching script:
- "Switch to Development" (or similar name with "development"/"dev")
- "Switch to Staging" (or similar name with "staging")
- "Switch to Production" (or similar name with "production"/"prod")

### 2. Status Bar Customization (`.vscode/settings.json`)
Configure visual environment indicators:
- Status bar background color (use `"statusBar.background"` or `"workbench.colorCustomizations"`)
- Window title showing environment (use `"window.title"`)

Suggested colors:
- Development: Blue (`#007acc`)
- Staging: Orange (`#ff9800`)
- Production: Red (`#f44336`)

### 3. Switching Script
Create either `scripts/switch-env.sh` (Bash) or `scripts/switch_env.py` (Python) that:
- Accepts environment argument: `dev`/`development`, `staging`, or `prod`/`production`
- Copies corresponding `.env.{environment}` to `.env`
- For production, requires explicit confirmation (e.g., typing "CONFIRM PRODUCTION" or similar safeguard)
- Updates `.vscode/settings.json` with appropriate status bar color
- Provides clear output message

**Bash Example Structure:**