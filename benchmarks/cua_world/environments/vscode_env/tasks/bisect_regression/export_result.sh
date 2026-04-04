#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Bisect Regression Result ==="

REPO_PATH="/home/ga/workspace/payment-service"

# Give user time to finish and save their work
sleep 2

# Export BISECT_RESULTS.md if it exists
RESULTS_FILE="$REPO_PATH/BISECT_RESULTS.md"
if [ -f "$RESULTS_FILE" ]; then
    echo "✓ Found BISECT_RESULTS.md, copying to /tmp"
    sudo -u ga cp "$RESULTS_FILE" /tmp/bisect_results.md
    chmod 644 /tmp/bisect_results.md
else
    echo "⚠️ BISECT_RESULTS.md not found"
    echo "File not created by user" > /tmp/bisect_results.md
fi

# Export git log to verify commits exist
if [ -d "$REPO_PATH/.git" ]; then
    echo "Exporting git log..."
    cd "$REPO_PATH"
    sudo -u ga git log --all --format="%H|%s|%an|%ad" > /tmp/git_log_bisect.txt 2>&1 || echo "No commits" > /tmp/git_log_bisect.txt
    
    echo "Exporting git status..."
    sudo -u ga git status --porcelain > /tmp/git_status_bisect.txt 2>&1 || echo "" > /tmp/git_status_bisect.txt
    
    # Check if bisect is still active
    if [ -f "$REPO_PATH/.git/BISECT_LOG" ]; then
        echo "Git bisect still active (BISECT_LOG exists)"
        sudo -u ga cp "$REPO_PATH/.git/BISECT_LOG" /tmp/bisect_log_active.txt 2>/dev/null || true
    else
        echo "Git bisect properly finished (no BISECT_LOG)"
        echo "BISECT_COMPLETED" > /tmp/bisect_log_active.txt
    fi
    
    # Export current branch
    sudo -u ga git branch --show-current > /tmp/current_branch.txt 2>&1 || echo "unknown" > /tmp/current_branch.txt
    
    echo "✓ Git data exported to /tmp"
else
    echo "⚠️ Git repository not found"
    echo "No repository" > /tmp/git_log_bisect.txt
fi

# Export the bad commit SHA that was stored during setup
if [ -f /tmp/bad_commit_sha.txt ]; then
    echo "✓ Bad commit reference found"
else
    echo "⚠️ Bad commit reference not found"
fi

echo "✅ Export complete"
echo "Repository: $REPO_PATH"
echo "Results file: /tmp/bisect_results.md"