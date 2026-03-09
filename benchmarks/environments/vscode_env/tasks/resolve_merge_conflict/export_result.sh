#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Merge Conflict Resolution Result ==="

REPO_PATH="/home/ga/workspace/pricing-app"

# Ensure files are saved
echo "Ensuring files are saved..."
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Give time for any pending Git operations to complete
sleep 2

# Export Git state for verification
if [ -d "$REPO_PATH/.git" ]; then
    echo "Exporting Git state..."
    
    cd "$REPO_PATH"
    
    # Export git log
    sudo -u ga git log --all --format="%H|%s|%an|%ad" -n 10 > /tmp/merge_git_log.txt 2>&1 || echo "No commits" > /tmp/merge_git_log.txt
    
    # Export git status
    sudo -u ga git status --porcelain > /tmp/merge_git_status.txt 2>&1 || echo "" > /tmp/merge_git_status.txt
    
    # Export verbose git status for debugging
    sudo -u ga git status > /tmp/merge_git_status_verbose.txt 2>&1 || echo "" > /tmp/merge_git_status_verbose.txt
    
    # Check if MERGE_HEAD exists (indicates merge in progress)
    if [ -f "$REPO_PATH/.git/MERGE_HEAD" ]; then
        echo "MERGE_IN_PROGRESS" > /tmp/merge_state.txt
        cat "$REPO_PATH/.git/MERGE_HEAD" > /tmp/merge_head.txt
    else
        echo "MERGE_COMPLETED" > /tmp/merge_state.txt
        echo "" > /tmp/merge_head.txt
    fi
    
    # Export the latest commit parents (to check if it's a merge commit)
    sudo -u ga git rev-list --parents -n 1 HEAD > /tmp/merge_commit_parents.txt 2>&1 || echo "" > /tmp/merge_commit_parents.txt
    
    # Export file contents
    if [ -f "$REPO_PATH/src/utils.py" ]; then
        cat "$REPO_PATH/src/utils.py" > /tmp/merge_utils_py.txt
    else
        echo "FILE_NOT_FOUND" > /tmp/merge_utils_py.txt
    fi
    
    if [ -f "$REPO_PATH/src/config.py" ]; then
        cat "$REPO_PATH/src/config.py" > /tmp/merge_config_py.txt
    else
        echo "FILE_NOT_FOUND" > /tmp/merge_config_py.txt
    fi
    
    echo "✅ Git data exported to /tmp"
else
    echo "⚠️ Git repository not found at $REPO_PATH"
    echo "No git repository" > /tmp/merge_git_log.txt
    echo "" > /tmp/merge_git_status.txt
    echo "REPO_NOT_FOUND" > /tmp/merge_state.txt
fi

echo "✅ Export complete"
echo "Repository: $REPO_PATH"
ls -la /tmp/merge_* 2>/dev/null || true