#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Transform API Response Result ==="

RESULT_FILE="/home/ga/workspace/data/users_export.csv"

# Try to save any open files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save in VSCode; continuing"
}

# Wait a moment for file to be written
sleep 2

# Check if result file exists
if [ -f "$RESULT_FILE" ]; then
    echo "✅ CSV file found at $RESULT_FILE"
    # Copy to /tmp for verifier
    cp "$RESULT_FILE" /tmp/users_export.csv
    echo "Exported CSV to /tmp/users_export.csv"
    
    # Show file info
    echo "File size: $(stat -f%z "$RESULT_FILE" 2>/dev/null || stat -c%s "$RESULT_FILE" 2>/dev/null || echo 'unknown')"
    echo "Line count: $(wc -l < "$RESULT_FILE" 2>/dev/null || echo 'unknown')"
    
    # Show first few lines for debugging
    echo "First 3 lines of CSV:"
    head -n 3 "$RESULT_FILE" 2>/dev/null || echo "Could not read file"
else
    echo "⚠️ Warning: CSV file not found at $RESULT_FILE"
    echo "Creating empty placeholder file"
    touch /tmp/users_export.csv
fi

echo "=== Export complete ==="