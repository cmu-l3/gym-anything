#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Validate Data Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/data_validation"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to save files via VSCode; continuing"
}

# Export all relevant files to /tmp for verifier
echo "Exporting workspace files to /tmp..."

# Copy key files to /tmp
sudo -u ga cp "$WORKSPACE_DIR/process_orders.py" /tmp/process_orders.py 2>/dev/null || echo "process_orders.py not found" > /tmp/process_orders.py
sudo -u ga cp "$WORKSPACE_DIR/orders.csv" /tmp/orders.csv 2>/dev/null || echo "" > /tmp/orders.csv
sudo -u ga cp "$WORKSPACE_DIR/report.json" /tmp/report.json 2>/dev/null || echo "{}" > /tmp/report.json
sudo -u ga cp "$WORKSPACE_DIR/VALIDATION.md" /tmp/VALIDATION.md 2>/dev/null || echo "" > /tmp/VALIDATION.md
sudo -u ga cp "$WORKSPACE_DIR/test_orders.py" /tmp/test_orders.py 2>/dev/null || echo "" > /tmp/test_orders.py

# List directory contents for debugging
ls -la "$WORKSPACE_DIR" > /tmp/workspace_listing.txt 2>&1 || echo "" > /tmp/workspace_listing.txt

# Export git log
cd "$WORKSPACE_DIR"
sudo -u ga git log --oneline --all > /tmp/git_log.txt 2>&1 || echo "" > /tmp/git_log.txt

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"
echo "Exported files to /tmp/"