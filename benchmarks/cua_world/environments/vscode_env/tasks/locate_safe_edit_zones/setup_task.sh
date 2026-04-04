#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Locate Safe Edit Zones Task ==="

WORKSPACE_DIR="/home/ga/workspace/api-client-project"
ASSETS_DIR="/workspace/tasks/locate_safe_edit_zones/assets"

# Create workspace
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Copy project structure from assets
echo "Creating project structure..."
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/generated/api"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/generated/models"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/custom"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.openapi-generator"

# Copy all asset files to workspace
if [ -d "$ASSETS_DIR" ]; then
    sudo -u ga cp -r "$ASSETS_DIR"/* "$WORKSPACE_DIR/" 2>/dev/null || true
fi

# Ensure all files are owned by ga user
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initialize git repo (makes it feel like a real inherited project)
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.email "previous.dev@example.com"
sudo -u ga git config user.name "Previous Developer"
sudo -u ga git add .
sudo -u ga git commit -m "Initial project setup with generated API client" 2>/dev/null || true

# Open VSCode in the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the bug report for convenience
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/bug-report.txt'" 2>/dev/null || true
sleep 1

echo "=== Locate Safe Edit Zones Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read bug-report.txt to understand the 429 error problem"
echo "  2. Explore project structure (src/generated/, src/custom/)"
echo "  3. Look for 'DO NOT EDIT' warnings in generated files"
echo "  4. Find codegen.yml to understand generation process"
echo "  5. Identify safe edit zones (custom/ directory, wrapper files)"
echo "  6. Create SAFE_EDIT_GUIDE.md documenting your findings"
echo ""
echo "Workspace: $WORKSPACE_DIR"