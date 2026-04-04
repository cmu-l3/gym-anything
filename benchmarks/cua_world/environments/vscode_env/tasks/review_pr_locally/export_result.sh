#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Review PR Locally Result ==="

WORKSPACE_DIR="/home/ga/workspace/auth-service"

# Focus VSCode and save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save files; continuing"
}

sleep 2

# Export the review notes file (primary artifact)
if [ -f "$WORKSPACE_DIR/pr_review_notes.txt" ]; then
    cp "$WORKSPACE_DIR/pr_review_notes.txt" /tmp/pr_review_notes.txt
    echo "✅ Exported pr_review_notes.txt"
else
    echo "⚠️ WARNING: pr_review_notes.txt not found"
    touch /tmp/pr_review_notes.txt
fi

# Export current branch info
cd "$WORKSPACE_DIR"
sudo -u ga git branch --show-current > /tmp/current_branch.txt 2>&1 || echo "unknown" > /tmp/current_branch.txt
echo "Current branch: $(cat /tmp/current_branch.txt)"

# Export recent commits
sudo -u ga git log --oneline -10 > /tmp/recent_commits.txt 2>&1 || echo "" > /tmp/recent_commits.txt

# Export Git status
sudo -u ga git status --short > /tmp/git_status.txt 2>&1 || echo "" > /tmp/git_status.txt

# Export diff stats if on the PR branch
if [ "$(cat /tmp/current_branch.txt)" = "fix/sanitize-user-input" ]; then
    sudo -u ga git diff main --stat > /tmp/diff_stats.txt 2>&1 || echo "" > /tmp/diff_stats.txt
else
    echo "Not on PR branch" > /tmp/diff_stats.txt
fi

# List all files in workspace for debugging
ls -la "$WORKSPACE_DIR" > /tmp/workspace_listing.txt 2>&1 || echo "" > /tmp/workspace_listing.txt

echo "✅ Export complete"
echo "Review notes: /tmp/pr_review_notes.txt"
echo "Current branch: $(cat /tmp/current_branch.txt)"