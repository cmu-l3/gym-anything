#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Environment Variables Configuration Task ==="

WORKSPACE_DIR="/home/ga/workspace/env_task"
ASSETS_DIR="/workspace/tasks/setup_env_variables/assets"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Copy Node.js application files
echo "Copying application files..."
if [ -f "$ASSETS_DIR/app.js" ]; then
    sudo -u ga cp "$ASSETS_DIR/app.js" "$WORKSPACE_DIR/"
else
    echo "⚠️ Warning: app.js not found in assets"
fi

if [ -f "$ASSETS_DIR/package.json" ]; then
    sudo -u ga cp "$ASSETS_DIR/package.json" "$WORKSPACE_DIR/"
else
    echo "⚠️ Warning: package.json not found in assets"
fi

# Copy starter launch.json (incomplete - missing envFile)
if [ -f "$ASSETS_DIR/starter_launch.json" ]; then
    sudo -u ga cp "$ASSETS_DIR/starter_launch.json" "$WORKSPACE_DIR/.vscode/launch.json"
else
    echo "⚠️ Warning: starter_launch.json not found in assets"
fi

# Copy .gitignore (already includes .env)
if [ -f "$ASSETS_DIR/starter_gitignore" ]; then
    sudo -u ga cp "$ASSETS_DIR/starter_gitignore" "$WORKSPACE_DIR/.gitignore"
else
    echo "⚠️ Warning: starter_gitignore not found in assets"
fi

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Install npm dependencies (dotenv package)
echo "Installing npm dependencies..."
cd "$WORKSPACE_DIR"
sudo -u ga npm install dotenv 2>&1 | head -n 10 || echo "npm install completed with warnings"

# Ensure .env does NOT exist (agent must create it)
if [ -f "$WORKSPACE_DIR/.env" ]; then
    rm -f "$WORKSPACE_DIR/.env"
    echo "Removed existing .env file (agent must create it)"
fi

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Environment Variables Configuration Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create .env file with DATABASE_URL, API_KEY, PORT, NODE_ENV"
echo "  2. Edit .vscode/launch.json to add envFile property"
echo "  3. Save all files"
echo ""
echo "Workspace: $WORKSPACE_DIR"
echo "Files: app.js, package.json, .vscode/launch.json, .gitignore"