#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Resolve Formatter Conflict Task ==="

WORKSPACE_DIR="/home/ga/workspace/webapp"
ASSETS_DIR="/workspace/tasks/resolve_formatter_conflict/assets"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/components"
echo "Created workspace directory: $WORKSPACE_DIR"

# Copy configuration files from assets
echo "Copying configuration files..."
sudo -u ga cp "$ASSETS_DIR/package.json" "$WORKSPACE_DIR/"
sudo -u ga cp "$ASSETS_DIR/.eslintrc.json" "$WORKSPACE_DIR/"
sudo -u ga cp "$ASSETS_DIR/.prettierrc.json" "$WORKSPACE_DIR/"

# Copy source files
echo "Copying source files..."
sudo -u ga cp "$ASSETS_DIR/src/index.js" "$WORKSPACE_DIR/src/"
sudo -u ga cp "$ASSETS_DIR/src/utils.js" "$WORKSPACE_DIR/src/"
sudo -u ga cp "$ASSETS_DIR/README.md" "$WORKSPACE_DIR/" || true

# Install existing dependencies (eslint and prettier only, NOT eslint-config-prettier)
echo "Installing base dependencies (eslint and prettier)..."
cd "$WORKSPACE_DIR"
sudo -u ga npm install --silent --no-audit 2>&1 | grep -v "npm WARN" || true

# Ensure proper permissions
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode to the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --reuse-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Resolve Formatter Conflict Task Setup Complete ==="
echo "📝 Workspace: $WORKSPACE_DIR"
echo "📝 Current state:"
echo "  - package.json has eslint and prettier (NO eslint-config-prettier)"
echo "  - .eslintrc.json has conflicting formatting rules"
echo "  - .prettierrc.json has different preferences"
echo ""
echo "📋 Instructions:"
echo "  1. Open integrated terminal (Ctrl+\`)"
echo "  2. Run: npm install --save-dev eslint-config-prettier"
echo "  3. Open .eslintrc.json"
echo "  4. Add 'prettier' to the extends array"
echo "  5. Save files (Ctrl+S)"