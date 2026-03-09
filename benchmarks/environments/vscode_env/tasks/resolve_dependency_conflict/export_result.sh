#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Dependency Conflict Resolution Result ==="

WORKSPACE_DIR="/home/ga/workspace/conflict_app"
cd "$WORKSPACE_DIR"

# Save the file one more time to ensure changes are persisted
focus_vscode_window
sleep 1
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" || true
sleep 2

# Wait for file to be saved
wait_for_file "$WORKSPACE_DIR/package.json" 3

echo "Attempting npm install to test resolution..."
# Clean install to test current state
sudo -u ga rm -rf node_modules package-lock.json 2>/dev/null || true

# Run npm install and capture output
cd "$WORKSPACE_DIR"
sudo -u ga npm install > /tmp/install_log.txt 2>&1
INSTALL_EXIT_CODE=$?
echo "npm install exit code: $INSTALL_EXIT_CODE" >> /tmp/install_log.txt

# Show install log for debugging
echo "Install log preview:"
head -n 20 /tmp/install_log.txt

# Try to start the app briefly to verify it can run
echo "Testing if application can start..."
timeout 3s sudo -u ga npm start > /tmp/start_log.txt 2>&1 || true
echo "Application start test completed"

# Copy files to /tmp for verifier access
sudo -u ga cp "$WORKSPACE_DIR/package.json" /tmp/package.json 2>/dev/null || true
sudo -u ga cp "$WORKSPACE_DIR/.original_package.json" /tmp/original_package.json 2>/dev/null || true
sudo -u ga cp "$WORKSPACE_DIR/package-lock.json" /tmp/package-lock.json 2>/dev/null || true

# Ensure permissions
chmod 644 /tmp/package.json /tmp/original_package.json /tmp/install_log.txt /tmp/start_log.txt 2>/dev/null || true

echo "✅ Export complete"
echo "Files exported:"
echo "  - /tmp/package.json (modified)"
echo "  - /tmp/original_package.json (backup)"
echo "  - /tmp/install_log.txt (npm install output)"
echo "  - /tmp/start_log.txt (npm start test)"
echo ""
echo "Workspace: $WORKSPACE_DIR"