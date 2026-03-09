#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Customer Bug Investigation Result ==="

# Focus VSCode and save any open files
focus_vscode_window
sleep 1

# Save current file
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save via keyboard; continuing"
}

# Wait for file to be written
sleep 2

# Copy the critical file to /tmp for verification
WORKSPACE_DIR="/home/ga/workspace/analytics_app"
RESULTS_DIR="/tmp/bug_investigation_results"

sudo -u ga mkdir -p "$RESULTS_DIR"

# Copy modified source file
if [ -f "$WORKSPACE_DIR/src/date_utils.py" ]; then
    sudo -u ga cp "$WORKSPACE_DIR/src/date_utils.py" "$RESULTS_DIR/" 2>&1 || echo "Failed to copy date_utils.py"
    echo "✅ Copied date_utils.py to results directory"
else
    echo "⚠️ date_utils.py not found"
fi

# Copy other files for debugging
sudo -u ga cp "$WORKSPACE_DIR/support_ticket_2847.txt" "$RESULTS_DIR/" 2>/dev/null || true
sudo -u ga cp "$WORKSPACE_DIR/customer_data_sample.csv" "$RESULTS_DIR/" 2>/dev/null || true

# Export file listing
ls -laR "$WORKSPACE_DIR" > "$RESULTS_DIR/file_listing.txt" 2>&1 || true

echo "✅ Export complete - results in $RESULTS_DIR"