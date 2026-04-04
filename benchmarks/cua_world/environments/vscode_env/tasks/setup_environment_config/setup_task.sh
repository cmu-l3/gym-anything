#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Environment Config Task ==="

WORKSPACE_DIR="/home/ga/workspace/env_config_project"
TASK_ASSETS="/workspace/tasks/setup_environment_config/assets"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Copy application files from assets
echo "Copying application files..."
sudo -u ga cp "$TASK_ASSETS/server.js" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/config.js" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/package.json" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/.env.example" "$WORKSPACE_DIR/"

# Create task instructions
cat > "$WORKSPACE_DIR/TASK_INSTRUCTIONS.md" << 'EOF'
# Environment Setup Task

## Problem
This Node.js application requires environment variables to run, but the `.env` file is missing.

## Your Goal
1. Search the codebase for `process.env` references to find required variables
2. Create a `.env` file in the project root (same directory as package.json)
3. Add all required environment variables with appropriate values
4. Test that the application starts successfully

## Hints
- Use VSCode's search (Ctrl+Shift+F) to find all `process.env` references
- Check `server.js` and `config.js` for required variables
- Refer to `.env.example` for file format (but it doesn't have values)
- Required variables have NO default values (will crash if missing)
- Test by running: `npm start` in the integrated terminal

## Example .env format: