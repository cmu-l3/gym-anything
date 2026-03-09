#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract from Massive Log Result ==="

WORKSPACE_DIR="/home/ga/workspace/incident_logs"

# Give any pending operations time to complete
sleep 2

# Try to save any open files
focus_vscode_window 2>/dev/null || true
{
    safe_xdotool ga :1 key --delay 100 ctrl+s 2>/dev/null || true
} || {
    echo "⚠️ Could not send save command"
}

sleep 1

# Export VSCode settings (both user and workspace)
echo "Exporting VSCode settings..."
mkdir -p /tmp/vscode_settings

if [ -f "/home/ga/.config/Code/User/settings.json" ]; then
    cp "/home/ga/.config/Code/User/settings.json" /tmp/vscode_settings/user_settings.json
else
    echo "{}" > /tmp/vscode_settings/user_settings.json
fi

if [ -f "$WORKSPACE_DIR/.vscode/settings.json" ]; then
    cp "$WORKSPACE_DIR/.vscode/settings.json" /tmp/vscode_settings/workspace_settings.json
else
    echo "{}" > /tmp/vscode_settings/workspace_settings.json
fi

# Export extracted file if it exists
echo "Checking for extracted file..."
if [ -f "$WORKSPACE_DIR/payment_failures.log" ]; then
    echo "✓ Extracted file found"
    cp "$WORKSPACE_DIR/payment_failures.log" /tmp/payment_failures.log
    
    # Generate statistics
    wc -l /tmp/payment_failures.log > /tmp/extraction_stats.txt 2>&1 || echo "0" > /tmp/extraction_stats.txt
    grep -c "CRITICAL" /tmp/payment_failures.log >> /tmp/extraction_stats.txt 2>&1 || echo "0" >> /tmp/extraction_stats.txt
    ls -lh /tmp/payment_failures.log >> /tmp/extraction_stats.txt 2>&1 || true
else
    echo "⚠️ Extracted file not found at $WORKSPACE_DIR/payment_failures.log"
    echo "File not found" > /tmp/payment_failures.log
    echo "0" > /tmp/extraction_stats.txt
fi

# Export bash history (shows terminal commands used)
echo "Exporting bash history..."
if [ -f "/home/ga/.bash_history" ]; then
    cp /home/ga/.bash_history /tmp/bash_history.txt
else
    echo "" > /tmp/bash_history.txt
fi

# Export workspace file list
echo "Exporting workspace file list..."
ls -lh "$WORKSPACE_DIR" > /tmp/workspace_files.txt 2>&1 || echo "Workspace not found" > /tmp/workspace_files.txt

echo "✅ Export complete"
echo "Results location: /tmp/"
echo "  - user_settings.json, workspace_settings.json"
echo "  - payment_failures.log"
echo "  - bash_history.txt"
echo "  - extraction_stats.txt"