#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Pair Programming Setup Result ==="

WORKSPACE_DIR="/home/ga/workspace/pair_session"
SETTINGS_FILE="/home/ga/.config/Code/User/settings.json"
SESSION_NOTES="$WORKSPACE_DIR/session_notes.txt"

# Focus VSCode and trigger save
echo "Focusing VSCode and saving..."
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

sleep 2

# Export VSCode settings to /tmp for verifier
echo "Exporting VSCode settings..."
if [ -f "$SETTINGS_FILE" ]; then
    cp "$SETTINGS_FILE" /tmp/vscode_settings.json
    echo "✅ Settings exported to /tmp/vscode_settings.json"
else
    echo "⚠️ Settings file not found at $SETTINGS_FILE"
    echo "{}" > /tmp/vscode_settings.json
fi

# Export session notes if they exist
echo "Exporting session notes..."
if [ -f "$SESSION_NOTES" ]; then
    cp "$SESSION_NOTES" /tmp/session_notes.txt
    echo "✅ Session notes exported to /tmp/session_notes.txt"
else
    echo "⚠️ Session notes not found at $SESSION_NOTES"
    echo "" > /tmp/session_notes.txt
fi

# Create a summary for debugging
cat > /tmp/pair_setup_summary.txt << EOF
Pair Programming Setup Export Summary
======================================
Timestamp: $(date)
Settings File: $([ -f "$SETTINGS_FILE" ] && echo "Found" || echo "Missing")
Session Notes: $([ -f "$SESSION_NOTES" ] && echo "Found" || echo "Missing")
Workspace: $WORKSPACE_DIR

Settings Content (first 5 lines):
$(head -n 5 /tmp/vscode_settings.json 2>/dev/null || echo "N/A")

Session Notes Content (first 5 lines):
$(head -n 5 /tmp/session_notes.txt 2>/dev/null || echo "N/A")
EOF

echo "✅ Export complete"
echo "Files exported:"
echo "  - /tmp/vscode_settings.json"
echo "  - /tmp/session_notes.txt"
echo "  - /tmp/pair_setup_summary.txt"