#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Refine Regex Validator Result ==="

WORKSPACE_DIR="/home/ga/workspace/email_validation"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to send save all command; continuing"
}

# Wait for files to be written
sleep 2

# Copy validator.py to /tmp for verification
if [ -f "$WORKSPACE_DIR/validator.py" ]; then
    cp "$WORKSPACE_DIR/validator.py" /tmp/validator.py
    echo "✅ Copied validator.py to /tmp"
else
    echo "⚠️ validator.py not found"
    echo "" > /tmp/validator.py
fi

# Find and copy test runner scripts to /tmp
echo "Looking for test runner scripts..."
found_test_runner=false
for test_file in "$WORKSPACE_DIR"/test_*.py "$WORKSPACE_DIR"/run_*.py; do
    if [ -f "$test_file" ]; then
        filename=$(basename "$test_file")
        cp "$test_file" "/tmp/$filename"
        echo "✅ Copied test runner: $filename"
        found_test_runner=true
    fi
done

if [ "$found_test_runner" = false ]; then
    echo "⚠️ No test runner found (test_*.py or run_*.py)"
fi

# Copy test_cases.txt for reference
if [ -f "$WORKSPACE_DIR/test_cases.txt" ]; then
    cp "$WORKSPACE_DIR/test_cases.txt" /tmp/test_cases.txt
    echo "✅ Copied test_cases.txt to /tmp"
fi

# List all Python files in workspace (for debugging)
echo "Python files in workspace:"
ls -la "$WORKSPACE_DIR"/*.py 2>/dev/null || echo "No Python files found"

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"