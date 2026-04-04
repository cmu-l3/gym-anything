#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Prepare Release Notes Result ==="

WORKSPACE_DIR="/home/ga/workspace/webapp"
CHANGELOG_PATH="$WORKSPACE_DIR/CHANGELOG.md"

# Ensure file is saved
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save command; continuing"
}

sleep 2

# Export CHANGELOG.md to /tmp for verifier
if [ -f "$CHANGELOG_PATH" ]; then
    echo "Copying CHANGELOG.md to /tmp..."
    cp "$CHANGELOG_PATH" /tmp/CHANGELOG.md
    echo "✅ CHANGELOG.md exported"
    echo ""
    echo "=== CHANGELOG.md Contents ==="
    cat "$CHANGELOG_PATH"
    echo ""
    echo "=== File Info ==="
    ls -lh "$CHANGELOG_PATH"
else
    echo "⚠️ CHANGELOG.md not found at $CHANGELOG_PATH"
    touch /tmp/CHANGELOG.md  # Create empty file so verifier doesn't error
fi

# Export git log for reference
cd "$WORKSPACE_DIR"
echo "Exporting git log since v1.5.0..."
sudo -u ga git log v1.5.0..HEAD --oneline > /tmp/git_commits.txt 2>&1 || echo "No commits" > /tmp/git_commits.txt

echo "✅ Export complete"