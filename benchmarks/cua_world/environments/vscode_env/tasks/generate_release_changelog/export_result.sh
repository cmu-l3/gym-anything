#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Generate Release Changelog Result ==="

WORKSPACE_DIR="/home/ga/workspace/sample-project"
CHANGELOG_PATH="$WORKSPACE_DIR/CHANGELOG.md"

# Try to save the file if VSCode is focused
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Wait for changelog file to exist
wait_for_file "$CHANGELOG_PATH" 3 || echo "⚠️ CHANGELOG.md not found yet"

# Export git log for verifier reference
cd "$WORKSPACE_DIR"
echo "Exporting git log..."
sudo -u ga git log v2.0.0..HEAD --format="%H|%s|%an|%ad" > /tmp/git_log_changelog.txt 2>&1 || echo "No commits" > /tmp/git_log_changelog.txt

# Export git tag info
sudo -u ga git tag -l > /tmp/git_tags.txt 2>&1 || echo "" > /tmp/git_tags.txt

# Copy changelog to /tmp if it exists
if [ -f "$CHANGELOG_PATH" ]; then
    cp "$CHANGELOG_PATH" /tmp/CHANGELOG.md 2>&1 || echo "Failed to copy CHANGELOG.md"
    echo "✅ CHANGELOG.md exported to /tmp"
    echo "Changelog preview (first 20 lines):"
    head -n 20 "$CHANGELOG_PATH" || echo "Could not read changelog"
else
    echo "⚠️ CHANGELOG.md not found at $CHANGELOG_PATH"
    echo "" > /tmp/CHANGELOG.md
fi

echo "✅ Export complete"
echo "Repository: $WORKSPACE_DIR"