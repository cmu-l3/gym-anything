#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Code Archaeology Result ==="

WORKSPACE_DIR="/home/ga/workspace/pricing-project"

# Try to save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save files; continuing"
}

# Export git log to /tmp
if [ -d "$WORKSPACE_DIR/.git" ]; then
    echo "Exporting git log..."
    cd "$WORKSPACE_DIR"
    sudo -u ga git log --all --format="%H|%s|%an|%ae|%ad" > /tmp/git_archaeology_log.txt 2>&1 || echo "No commits" > /tmp/git_archaeology_log.txt
    
    echo "Exporting git blame for discount.js..."
    sudo -u ga git blame src/pricing/discount.js > /tmp/git_blame_discount.txt 2>&1 || echo "No blame data" > /tmp/git_blame_discount.txt
    
    echo "✅ Git data exported to /tmp"
else
    echo "⚠️ Git repository not found"
    echo "No repository" > /tmp/git_archaeology_log.txt
fi

# Check if investigation file exists
INVESTIGATION_FILE="$WORKSPACE_DIR/INVESTIGATION.md"
if [ -f "$INVESTIGATION_FILE" ]; then
    echo "✅ INVESTIGATION.md found"
    cat "$INVESTIGATION_FILE"
else
    echo "⚠️ INVESTIGATION.md not found"
fi

# Give time for any final writes
sleep 2

echo "✅ Export complete"
echo "Investigation file: $INVESTIGATION_FILE"