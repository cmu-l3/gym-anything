#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Triage Production Logs Result ==="

WORKSPACE_DIR="/home/ga/workspace/incident_logs"

# Focus VSCode and save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save via VSCode; continuing"
}

# Wait for triage summary file if it exists
if [ -f "$WORKSPACE_DIR/triage_summary.md" ]; then
    wait_for_file "$WORKSPACE_DIR/triage_summary.md" 3
    echo "✅ Triage summary found"
    echo "Summary preview (first 20 lines):"
    head -20 "$WORKSPACE_DIR/triage_summary.md"
else
    echo "⚠️ Warning: triage_summary.md not found"
fi

# Export file metadata to /tmp for verification
if [ -f "$WORKSPACE_DIR/triage_summary.md" ]; then
    wc -l "$WORKSPACE_DIR/triage_summary.md" > /tmp/triage_summary_stats.txt
    ls -lh "$WORKSPACE_DIR/triage_summary.md" >> /tmp/triage_summary_stats.txt
    echo "✅ Exported summary stats to /tmp"
fi

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"