#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Salvage Interrupted Work Result ==="

REPO_PATH="/home/ga/workspace/api-server"

# Ensure all changes are saved
focus_vscode_window
{
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
} || {
    echo "⚠️ Failed to focus VSCode window; continuing"
}

sleep 2

if [ ! -d "$REPO_PATH/.git" ]; then
    echo "⚠️ Git repository not found at $REPO_PATH"
    echo "No git repository" > /tmp/salvage_git_log_main.txt
    echo "No git repository" > /tmp/salvage_git_log_feature.txt
    echo "" > /tmp/salvage_git_status.txt
    echo "" > /tmp/salvage_git_branches.txt
    echo "main" > /tmp/salvage_current_branch.txt
    exit 0
fi

cd "$REPO_PATH"

# Export current branch
echo "Exporting current branch..."
sudo -u ga git branch --show-current > /tmp/salvage_current_branch.txt 2>&1 || echo "unknown" > /tmp/salvage_current_branch.txt

# Export all branches
echo "Exporting branch list..."
sudo -u ga git branch -a > /tmp/salvage_git_branches.txt 2>&1 || echo "" > /tmp/salvage_git_branches.txt

# Export git status
echo "Exporting git status..."
sudo -u ga git status --porcelain > /tmp/salvage_git_status.txt 2>&1 || echo "" > /tmp/salvage_git_status.txt

# Export git log for main branch
echo "Exporting main branch log..."
sudo -u ga git log main --format="%H|%s|%an|%ad" --all 2>/dev/null > /tmp/salvage_git_log_main.txt || echo "" > /tmp/salvage_git_log_main.txt

# Export git log for feature branch (if it exists)
echo "Exporting feature branch log..."
if sudo -u ga git rev-parse --verify feature/jwt-authentication >/dev/null 2>&1; then
    sudo -u ga git log feature/jwt-authentication --format="%H|%s|%an|%ad" > /tmp/salvage_git_log_feature.txt 2>&1 || echo "" > /tmp/salvage_git_log_feature.txt
else
    echo "Branch does not exist" > /tmp/salvage_git_log_feature.txt
fi

# Export diff stat for latest commit on main
echo "Exporting main latest commit diff..."
sudo -u ga git diff --name-only HEAD~1 HEAD 2>/dev/null > /tmp/salvage_main_commit_files.txt || echo "" > /tmp/salvage_main_commit_files.txt

# Export diff between main and feature branch (if feature exists)
echo "Exporting feature branch diff..."
if sudo -u ga git rev-parse --verify feature/jwt-authentication >/dev/null 2>&1; then
    sudo -u ga git diff --name-only main feature/jwt-authentication > /tmp/salvage_feature_diff_files.txt 2>&1 || echo "" > /tmp/salvage_feature_diff_files.txt
else
    echo "" > /tmp/salvage_feature_diff_files.txt
fi

# Export commit count on each branch
echo "Counting commits..."
sudo -u ga git rev-list --count main 2>/dev/null > /tmp/salvage_main_commit_count.txt || echo "0" > /tmp/salvage_main_commit_count.txt

if sudo -u ga git rev-parse --verify feature/jwt-authentication >/dev/null 2>&1; then
    sudo -u ga git rev-list --count feature/jwt-authentication 2>/dev/null > /tmp/salvage_feature_commit_count.txt || echo "0" > /tmp/salvage_feature_commit_count.txt
else
    echo "0" > /tmp/salvage_feature_commit_count.txt
fi

echo "✅ Git data exported to /tmp/salvage_*"
echo "Repository: $REPO_PATH"

# Show summary
echo ""
echo "=== Export Summary ==="
echo "Current branch: $(cat /tmp/salvage_current_branch.txt)"
echo "Git status: $(wc -l < /tmp/salvage_git_status.txt) uncommitted changes"
echo "Branches: $(cat /tmp/salvage_git_branches.txt | grep -v 'remotes' | wc -l)"