#!/bin/bash
# set -euo pipefail

echo "=== Exporting Git Bisect Result ==="

WORKSPACE_DIR="/home/ga/workspace"
REPO_DIR="$WORKSPACE_DIR/payment-service"
RESULT_FILE="$WORKSPACE_DIR/bisect_result.txt"

# Export directory for verification
EXPORT_DIR="/tmp/bisect_task_results"
sudo -u ga mkdir -p "$EXPORT_DIR"

# Copy bisect result if it exists
if [ -f "$RESULT_FILE" ]; then
    sudo -u ga cp "$RESULT_FILE" "$EXPORT_DIR/bisect_result.txt"
    echo "✓ Exported bisect result from $RESULT_FILE"
    echo "Result file size: $(stat -c%s "$RESULT_FILE") bytes"
else
    echo "⚠️ No bisect result found at $RESULT_FILE"
    echo "No bisect result file found" > "$EXPORT_DIR/bisect_result.txt"
fi

# Export git log for reference
if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR"
    sudo -u ga git log --all --oneline --no-decorate > "$EXPORT_DIR/git_log.txt" 2>&1 || echo "Failed to get git log" > "$EXPORT_DIR/git_log.txt"
    echo "✓ Exported git log"
    
    # Check if still in bisect mode
    if [ -f "$REPO_DIR/.git/BISECT_HEAD" ]; then
        echo "WARNING: Repository still in bisect mode" > "$EXPORT_DIR/bisect_warning.txt"
        echo "⚠️ Git is still in bisect mode"
    else
        echo "Bisect properly terminated" > "$EXPORT_DIR/bisect_status.txt"
        echo "✓ Bisect session was properly terminated"
    fi
    
    # Get the culprit commit hash for verification
    sudo -u ga git log --all --oneline --no-decorate --grep="Refactor Visa validation" > "$EXPORT_DIR/culprit_commit.txt" 2>&1 || true
else
    echo "⚠️ Git repository not found at $REPO_DIR"
fi

echo "✅ Export complete"
echo "Exported to: $EXPORT_DIR"
ls -la "$EXPORT_DIR"