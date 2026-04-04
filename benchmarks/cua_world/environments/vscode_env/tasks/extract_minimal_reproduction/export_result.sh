#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract Minimal Reproduction Result ==="

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to save all files; continuing"
}

# Wait for files to be written
sleep 2

# Check if files exist and copy to temp for easier verification
MRE_FILE="/home/ga/workspace/portfolio_risk/bug_report_mre.py"
REPORT_FILE="/home/ga/workspace/portfolio_risk/BUG_REPORT.md"

if [ -f "$MRE_FILE" ]; then
    echo "✅ MRE file found: $MRE_FILE"
    wc -l "$MRE_FILE" || true
else
    echo "⚠️ MRE file not found: $MRE_FILE"
fi

if [ -f "$REPORT_FILE" ]; then
    echo "✅ Bug report file found: $REPORT_FILE"
    wc -l "$REPORT_FILE" || true
else
    echo "⚠️ Bug report file not found: $REPORT_FILE"
fi

echo "✅ Export complete"