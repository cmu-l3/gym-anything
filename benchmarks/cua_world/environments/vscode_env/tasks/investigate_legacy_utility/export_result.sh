#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Investigate Legacy Utility Result ==="

WORKSPACE_DIR="/home/ga/workspace"

# Try to save any open files in VSCode
focus_vscode_window
{
  safe_xdotool ga :1 key --delay 200 ctrl+shift+s
  sleep 1
} || {
  echo "⚠️ Failed to trigger save all; continuing"
}

# Wait for report file to be written
sleep 2

# Export Git log for verifier reference
if [ -d "$WORKSPACE_DIR/.git" ]; then
    echo "Exporting Git log..."
    cd "$WORKSPACE_DIR"
    sudo -u ga git log --all --format="%H|%s|%an|%ad|%aI" > /tmp/archaeology_git_log.txt 2>&1 || echo "No commits" > /tmp/archaeology_git_log.txt
    
    echo "Exporting Git log with grep for sanitize..."
    sudo -u ga git log --all --grep="sanitize\|injection\|SQL" --format="%H|%s|%an|%ad" > /tmp/archaeology_relevant_commits.txt 2>&1 || echo "" > /tmp/archaeology_relevant_commits.txt
    
    echo "✅ Git data exported to /tmp"
fi

# Check if report exists and export status
if [ -f "$WORKSPACE_DIR/ARCHAEOLOGY_REPORT.md" ]; then
    echo "✅ Report file found at $WORKSPACE_DIR/ARCHAEOLOGY_REPORT.md"
    cp "$WORKSPACE_DIR/ARCHAEOLOGY_REPORT.md" /tmp/ARCHAEOLOGY_REPORT.md 2>&1 || echo "Failed to copy report"
    ls -lh "$WORKSPACE_DIR/ARCHAEOLOGY_REPORT.md"
else
    echo "⚠️ Report file not found at expected location"
    echo "NOT_FOUND" > /tmp/archaeology_report_status.txt
fi

# List all Python files for debugging
echo "Python files in workspace:"
find "$WORKSPACE_DIR" -name "*.py" -type f 2>/dev/null || true

echo "✅ Export complete"