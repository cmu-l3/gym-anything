#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug Intermittent Bug Task ==="

WORKSPACE_DIR="/home/ga/workspace/api_service"
ASSETS_DIR="/workspace/tasks/debug_intermittent_bug/assets"

# Create workspace structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/lib"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests/integration"

# Copy asset files
echo "Copying project files..."
sudo -u ga cp "$ASSETS_DIR/server.js" "$WORKSPACE_DIR/"
sudo -u ga cp "$ASSETS_DIR/database.js" "$WORKSPACE_DIR/lib/"
sudo -u ga cp "$ASSETS_DIR/cache.js" "$WORKSPACE_DIR/lib/"
sudo -u ga cp "$ASSETS_DIR/api_test.js" "$WORKSPACE_DIR/tests/integration/"
sudo -u ga cp "$ASSETS_DIR/package.json" "$WORKSPACE_DIR/"
sudo -u ga cp "$ASSETS_DIR/README.md" "$WORKSPACE_DIR/"

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Install npm dependencies
echo "Installing npm dependencies..."
cd "$WORKSPACE_DIR"
sudo -u ga npm install --silent 2>&1 | head -n 20 || echo "npm install completed with warnings"

# Wait a moment for npm to finish
sleep 2

echo "Project structure created at $WORKSPACE_DIR"

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

# Open relevant files in tabs
sleep 2
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/tests/integration/api_test.js'" || true
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/lib/database.js'" || true
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/README.md'" || true

echo "=== Debug Intermittent Bug Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review the flaky test in tests/integration/api_test.js"
echo "  2. Add diagnostic logging to lib/database.js (timestamps, connection pool state)"
echo "  3. Run 'npm test' multiple times in the integrated terminal (Ctrl+\`)"
echo "  4. Document findings in DEBUGGING_NOTES.md at workspace root"
echo "  5. Save all files (Ctrl+S)"
echo ""
echo "Workspace: $WORKSPACE_DIR"