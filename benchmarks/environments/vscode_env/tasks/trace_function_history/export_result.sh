#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Code Archaeology Result ==="

WORKSPACE_DIR="/home/ga/workspace/email_validator"

# Give user time to save their work
sleep 2

# Try to trigger save in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

sleep 1

# Export the FINDINGS.md file if it exists
FINDINGS_FILE="$WORKSPACE_DIR/FINDINGS.md"
if [ -f "$FINDINGS_FILE" ]; then
    echo "✅ FINDINGS.md found, copying to /tmp for verification"
    cp "$FINDINGS_FILE" /tmp/FINDINGS.md
    echo "File size: $(wc -c < $FINDINGS_FILE) bytes"
    echo "Preview:"
    head -n 10 "$FINDINGS_FILE"
else
    echo "⚠️ FINDINGS.md not found in $WORKSPACE_DIR"
    echo "" > /tmp/FINDINGS.md
fi

# Export git log for reference
cd "$WORKSPACE_DIR"
sudo -u ga git log --all --format="%H|%s|%an|%ad" > /tmp/git_log_archaeology.txt 2>&1 || echo "No commits" > /tmp/git_log_archaeology.txt

# Export current file state
if [ -f "$WORKSPACE_DIR/src/validators.py" ]; then
    cp "$WORKSPACE_DIR/src/validators.py" /tmp/validators_final.py
fi

echo "✅ Export complete"
echo "FINDINGS.md location: $FINDINGS_FILE"
echo "Git log exported to: /tmp/git_log_archaeology.txt"