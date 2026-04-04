#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Trace Cryptic Error Result ==="

WORKSPACE_DIR="/home/ga/workspace/debug_task"

# Save VSCode window first
focus_vscode_window
{
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 1
} || {
    echo "⚠️ Failed to focus VSCode window; continuing"
}

# Wait for files to be written
sleep 2

# Export launch.json if it exists
LAUNCH_JSON="$WORKSPACE_DIR/.vscode/launch.json"
if [ -f "$LAUNCH_JSON" ]; then
    echo "Exporting launch.json..."
    cp "$LAUNCH_JSON" /tmp/launch.json 2>&1 || echo "{}" > /tmp/launch.json
else
    echo "⚠️ launch.json not found"
    echo "{}" > /tmp/launch.json
fi

# Export modified data_processor.py
DATA_PROCESSOR="$WORKSPACE_DIR/data_processor.py"
if [ -f "$DATA_PROCESSOR" ]; then
    echo "Exporting data_processor.py..."
    cp "$DATA_PROCESSOR" /tmp/data_processor.py 2>&1 || touch /tmp/data_processor.py
else
    echo "⚠️ data_processor.py not found"
    touch /tmp/data_processor.py
fi

# Export findings.txt if it exists
FINDINGS="$WORKSPACE_DIR/findings.txt"
if [ -f "$FINDINGS" ]; then
    echo "Exporting findings.txt..."
    cp "$FINDINGS" /tmp/findings.txt 2>&1 || touch /tmp/findings.txt
else
    echo "⚠️ findings.txt not found"
    touch /tmp/findings.txt
fi

# Export original script for comparison
ORIGINAL_SCRIPT="/workspace/tasks/trace_cryptic_error/assets/data_processor.py"
if [ -f "$ORIGINAL_SCRIPT" ]; then
    cp "$ORIGINAL_SCRIPT" /tmp/data_processor_original.py 2>&1
fi

echo "✅ Export complete"
echo "Launch config: /tmp/launch.json"
echo "Modified script: /tmp/data_processor.py"
echo "Findings: /tmp/findings.txt"