#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Profile Slow Script Result ==="

WORKSPACE_DIR="/home/ga/workspace/profile_task"

# Try to save any open files
focus_vscode_window
{
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1
} || {
    echo "⚠️ Failed to save files; continuing"
}

# Wait for files to be written
sleep 2

# Copy relevant files to /tmp for verifier
echo "Copying files for verification..."

# Copy modified script
if [ -f "$WORKSPACE_DIR/data_processor.py" ]; then
    sudo -u ga cp "$WORKSPACE_DIR/data_processor.py" /tmp/data_processor.py
    echo "✅ Copied data_processor.py"
else
    echo "⚠️ data_processor.py not found"
fi

# Copy documentation if it exists
if [ -f "$WORKSPACE_DIR/performance_analysis.md" ]; then
    sudo -u ga cp "$WORKSPACE_DIR/performance_analysis.md" /tmp/performance_analysis.md
    echo "✅ Copied performance_analysis.md"
else
    echo "⚠️ performance_analysis.md not found"
    echo "" > /tmp/performance_analysis.md
fi

# Copy output file if it exists
if [ -f "$WORKSPACE_DIR/processed_data.csv" ]; then
    sudo -u ga cp "$WORKSPACE_DIR/processed_data.csv" /tmp/processed_data.csv
    echo "✅ Copied processed_data.csv"
else
    echo "⚠️ processed_data.csv not found"
fi

# Record if script was executed (check for output)
if [ -f "$WORKSPACE_DIR/processed_data.csv" ]; then
    echo "executed" > /tmp/script_execution_status.txt
else
    echo "not_executed" > /tmp/script_execution_status.txt
fi

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"