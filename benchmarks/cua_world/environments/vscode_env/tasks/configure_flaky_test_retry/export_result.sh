#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Flaky Test Retry Result ==="

# Focus VSCode and save all files
focus_vscode_window
sleep 1

# Try to save all files
echo "Attempting to save all files..."
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save commands; continuing"
}

# Wait for files to be written
sleep 2

# Verify files exist
WORKSPACE_DIR="/home/ga/workspace/flaky-test-project"
echo "Checking files..."

if [ -f "$WORKSPACE_DIR/jest.config.js" ]; then
    echo "✅ jest.config.js exists"
else
    echo "⚠️ jest.config.js not found"
fi

if [ -f "$WORKSPACE_DIR/tests/api.test.js" ]; then
    echo "✅ tests/api.test.js exists"
else
    echo "⚠️ tests/api.test.js not found"
fi

if [ -f "$WORKSPACE_DIR/FLAKY_TESTS.md" ]; then
    echo "✅ FLAKY_TESTS.md exists"
else
    echo "⚠️ FLAKY_TESTS.md not found (may be created by agent)"
fi

echo "✅ Export complete"
echo "Files location: $WORKSPACE_DIR"