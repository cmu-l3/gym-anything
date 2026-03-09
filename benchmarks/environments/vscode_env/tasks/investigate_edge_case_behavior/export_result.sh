#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Edge Case Investigation Results ==="

WORKSPACE_DIR="/home/ga/workspace/edge_case_investigation"

# Save all files to ensure changes are persisted
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 2
} || {
    echo "⚠️ Failed to save all files; continuing"
}

# Wait for files to be written
sleep 2

# Export the modified pricing.py
if [ -f "$WORKSPACE_DIR/utils/pricing.py" ]; then
    echo "Exporting pricing.py..."
    cp "$WORKSPACE_DIR/utils/pricing.py" /tmp/pricing_investigated.py
    echo "✅ Exported pricing.py"
else
    echo "⚠️ pricing.py not found"
    echo "" > /tmp/pricing_investigated.py
fi

# Export the analysis document if created
if [ -f "$WORKSPACE_DIR/edge_case_analysis.md" ]; then
    echo "Exporting edge_case_analysis.md..."
    cp "$WORKSPACE_DIR/edge_case_analysis.md" /tmp/edge_case_analysis.md
    echo "✅ Exported edge_case_analysis.md"
else
    echo "⚠️ edge_case_analysis.md not found"
    echo "" > /tmp/edge_case_analysis.md
fi

# Export file listing for debugging
ls -la "$WORKSPACE_DIR/" > /tmp/workspace_listing.txt 2>&1 || echo "No workspace" > /tmp/workspace_listing.txt

echo "✅ Export complete"
echo "Files exported to /tmp for verification"