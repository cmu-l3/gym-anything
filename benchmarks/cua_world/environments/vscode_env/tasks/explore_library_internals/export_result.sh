#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Library Exploration Result ==="

WORKSPACE_DIR="/home/ga/workspace/library_task"

# Try to save any open files
focus_vscode_window
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1

# Export test file if it exists
TEST_FILE="$WORKSPACE_DIR/test_datatools.py"
if [ -f "$TEST_FILE" ]; then
    echo "Copying test file for verification..."
    cp "$TEST_FILE" /tmp/test_datatools.py
    echo "✅ Test file exported to /tmp/test_datatools.py"
else
    echo "⚠️ Test file not found at $TEST_FILE"
    echo "" > /tmp/test_datatools.py
fi

# Export VSCode's recent files list for verification
VSCODE_STATE="/home/ga/.config/Code/User/globalStorage/storage.json"
if [ -f "$VSCODE_STATE" ]; then
    cp "$VSCODE_STATE" /tmp/vscode_storage.json
    echo "✅ VSCode state exported"
fi

# Export list of recently accessed files in the workspace
echo "Listing recently modified files in workspace..."
find "$WORKSPACE_DIR" -type f -name "*.py" -mmin -10 > /tmp/recent_files.txt 2>/dev/null || true

# Export list of files in virtual environment (to check access patterns)
SITE_PACKAGES="$WORKSPACE_DIR/venv/lib/python3.*/site-packages/datatools"
if ls $SITE_PACKAGES 2>/dev/null; then
    find $SITE_PACKAGES -type f -name "*.py" > /tmp/library_files.txt 2>/dev/null || true
    echo "✅ Library file list exported"
fi

# Export file access times for library files (to detect if they were opened)
if ls $SITE_PACKAGES 2>/dev/null; then
    stat $SITE_PACKAGES/*.py 2>/dev/null | grep -E "(File:|Access:)" > /tmp/library_access.txt || true
fi

echo "✅ Export complete"
echo "Test file: $TEST_FILE"
echo "Exported data available in /tmp/"