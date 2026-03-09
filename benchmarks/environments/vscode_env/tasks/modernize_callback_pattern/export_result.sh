#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Modernize Callback Pattern Result ==="

WORKSPACE_DIR="/home/ga/workspace/callback_migration"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️  Failed to send save command; continuing"
}

sleep 2

# Wait for files to be written
wait_for_file "$WORKSPACE_DIR/file_processor.js" 5
wait_for_file "$WORKSPACE_DIR/test/file_processor.test.js" 5

# Copy files to /tmp for verifier
echo "Copying files to /tmp for verification..."
cp "$WORKSPACE_DIR/file_processor.js" /tmp/file_processor.js 2>/dev/null || echo "Warning: Could not copy main file"
cp "$WORKSPACE_DIR/test/file_processor.test.js" /tmp/file_processor.test.js 2>/dev/null || echo "Warning: Could not copy test file"

# Run syntax check and export results
echo "Running syntax validation..."
cd "$WORKSPACE_DIR"
node --check file_processor.js > /tmp/syntax_check.txt 2>&1
echo $? > /tmp/syntax_check_code.txt

# Try to run tests (optional - don't fail if tests don't pass)
echo "Attempting to run tests..."
sudo -u ga npm test > /tmp/test_output.txt 2>&1 || echo "Tests did not pass (non-fatal)" > /tmp/test_output.txt

echo "✅ Export complete"
echo "Main file: $WORKSPACE_DIR/file_processor.js"
echo "Test file: $WORKSPACE_DIR/test/file_processor.test.js"