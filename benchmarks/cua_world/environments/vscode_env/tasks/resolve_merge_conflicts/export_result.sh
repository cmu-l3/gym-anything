#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Resolve Merge Conflicts Result ==="

REPO_PATH="/home/ga/workspace/merge_conflict_project"

# Try to save all files in VSCode before export
focus_vscode_window
{
    # Save all files (Ctrl+K S)
    su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+k" || true
    sleep 0.2
    su - ga -c "DISPLAY=:1 xdotool key --delay 100 s" || true
    sleep 1
} || {
    echo "⚠️ Failed to save files via VSCode; continuing"
}

# Export Git status
if [ -d "$REPO_PATH/.git" ]; then
    echo "Exporting git status..."
    cd "$REPO_PATH"
    
    # Get list of unmerged files
    sudo -u ga git diff --name-only --diff-filter=U > /tmp/unmerged_files.txt 2>&1 || echo "" > /tmp/unmerged_files.txt
    
    # Get overall status
    sudo -u ga git status --porcelain > /tmp/git_status.txt 2>&1 || echo "" > /tmp/git_status.txt
    
    # Get current branch
    sudo -u ga git branch --show-current > /tmp/git_branch.txt 2>&1 || echo "unknown" > /tmp/git_branch.txt
    
    echo "✅ Git data exported to /tmp"
else
    echo "⚠️ Git repository not found at $REPO_PATH"
    echo "" > /tmp/unmerged_files.txt
    echo "" > /tmp/git_status.txt
fi

# Wait a moment for files to be written
sleep 1

echo "✅ Export complete"
echo "Repository: $REPO_PATH"