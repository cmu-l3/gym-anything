#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Reproduce CI-Only Failure Result ==="

# Focus VSCode and save
focus_vscode_window
sleep 1

# Attempt to save the active file
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    echo "Sent Ctrl+S to save file"
} || {
    echo "⚠️ Failed to send save command; continuing anyway"
}

# Give time for file to be written
sleep 2

# Verify test file exists
TEST_FILE="/home/ga/workspace/payment_service/tests/test_payment.py"
if [ -f "$TEST_FILE" ]; then
    echo "✅ Test file found at $TEST_FILE"
    echo "File size: $(stat -f%z "$TEST_FILE" 2>/dev/null || stat -c%s "$TEST_FILE" 2>/dev/null) bytes"
else
    echo "⚠️ Warning: Test file not found at $TEST_FILE"
fi

# Export file content to temp location for debugging (optional)
if [ -f "$TEST_FILE" ]; then
    cp "$TEST_FILE" /tmp/test_payment_export.py 2>/dev/null || true
fi

echo "✅ Export complete"
echo "Test file path: $TEST_FILE"