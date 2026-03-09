#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Compare Git Branches Result ==="

REPO_PATH="/home/ga/workspace/auth_project"

# Export Git repository information
if [ -d "$REPO_PATH/.git" ]; then
    echo "Exporting Git branch information..."
    cd "$REPO_PATH"
    
    # List all branches
    sudo -u ga git branch -a > /tmp/git_branches.txt 2>&1 || echo "" > /tmp/git_branches.txt
    
    # Current branch
    sudo -u ga git branch --show-current > /tmp/git_current_branch.txt 2>&1 || echo "" > /tmp/git_current_branch.txt
    
    # Diff between branches for the specific file
    sudo -u ga git diff main..feature-auth -- config/database.py > /tmp/git_diff_database.txt 2>&1 || echo "" > /tmp/git_diff_database.txt
    
    # Get file content from both branches
    sudo -u ga git show main:config/database.py > /tmp/database_main.py 2>&1 || echo "" > /tmp/database_main.py
    sudo -u ga git show feature-auth:config/database.py > /tmp/database_feature.py 2>&1 || echo "" > /tmp/database_feature.py
    
    echo "✅ Git data exported"
else
    echo "⚠️ Git repository not found"
    echo "" > /tmp/git_branches.txt
    echo "" > /tmp/git_current_branch.txt
fi

# Export VSCode window information
echo "Exporting VSCode window state..."
wmctrl -l > /tmp/window_list.txt 2>&1 || echo "" > /tmp/window_list.txt
wmctrl -l -x > /tmp/window_list_detailed.txt 2>&1 || echo "" > /tmp/window_list_detailed.txt

# Get focused window title
xdotool getactivewindow getwindowname > /tmp/active_window_title.txt 2>&1 || echo "" > /tmp/active_window_title.txt

# Take screenshot for visual inspection
echo "Taking screenshot..."
DISPLAY=:1 import -window root /tmp/vscode_screenshot.png 2>&1 || echo "Screenshot failed"

# List VSCode processes to see what files might be open
ps aux | grep -i code | grep -v grep > /tmp/vscode_processes.txt 2>&1 || echo "" > /tmp/vscode_processes.txt

# Check if the specific file is open (check recent file access)
if [ -f "$REPO_PATH/config/database.py" ]; then
    ls -la "$REPO_PATH/config/database.py" > /tmp/database_file_stat.txt 2>&1
    stat "$REPO_PATH/config/database.py" > /tmp/database_file_stat_full.txt 2>&1 || true
fi

echo "✅ Export complete"
echo "Repository: $REPO_PATH"
echo "Window info saved to /tmp/window_*.txt"
echo "Screenshot saved to /tmp/vscode_screenshot.png"