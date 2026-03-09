#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Import Errors Result ==="

WORKSPACE_DIR="/home/ga/workspace/data_analysis"

# Focus VSCode and save current file
focus_vscode_window
{
safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to focus VSCode window; continuing"
}

# Wait for file to be saved
sleep 2
wait_for_file "$WORKSPACE_DIR/requirements.txt" 5

# Export requirements.txt to /tmp for verification
if [ -f "$WORKSPACE_DIR/requirements.txt" ]; then
    echo "Exporting requirements.txt..."
    cp "$WORKSPACE_DIR/requirements.txt" /tmp/requirements.txt
    echo "✅ requirements.txt exported"
    
    echo "=== Requirements.txt content ==="
    cat /tmp/requirements.txt
    echo "=== End of requirements.txt ==="
else
    echo "⚠️ requirements.txt not found"
    echo "File not found" > /tmp/requirements.txt
fi

# Test if imports work (without installing, just check syntax)
echo "Testing import script..."
cd "$WORKSPACE_DIR"
if timeout 10 python3 test_imports.py > /tmp/import_test_output.txt 2>&1; then
    echo "0" > /tmp/import_test_exitcode.txt
    echo "✅ Import test passed"
else
    echo "$?" > /tmp/import_test_exitcode.txt
    echo "⚠️ Import test failed (may need to install packages)"
fi

# Try running the main script (will fail if packages not installed, but that's ok)
cd "$WORKSPACE_DIR"
if timeout 10 python3 analyze_data.py > /tmp/script_output.txt 2>&1; then
    echo "0" > /tmp/script_exitcode.txt
else
    echo "$?" > /tmp/script_exitcode.txt
fi

echo "✅ Export complete"
echo "Requirements file: $WORKSPACE_DIR/requirements.txt"