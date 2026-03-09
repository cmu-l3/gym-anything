#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Exclude Heavy Directories Result ==="

WORKSPACE_DIR="/home/ga/workspace/monorepo_project"
SETTINGS_FILE="$WORKSPACE_DIR/.vscode/settings.json"

# Try to save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

# Wait for settings file to be written
sleep 2

# Copy settings file to /tmp for verification
if [ -f "$SETTINGS_FILE" ]; then
    echo "Copying settings.json to /tmp..."
    cp "$SETTINGS_FILE" /tmp/workspace_settings.json
    
    # Also create metadata
    echo "Settings file size: $(stat -c%s "$SETTINGS_FILE" 2>/dev/null || stat -f%z "$SETTINGS_FILE" 2>/dev/null)" > /tmp/settings_metadata.txt
    echo "Last modified: $(stat -c%y "$SETTINGS_FILE" 2>/dev/null || stat -f%Sm "$SETTINGS_FILE" 2>/dev/null)" >> /tmp/settings_metadata.txt
    
    echo "✅ Settings file exported"
    echo "File location: $SETTINGS_FILE"
    echo "File size: $(stat -c%s "$SETTINGS_FILE" 2>/dev/null || stat -f%z "$SETTINGS_FILE" 2>/dev/null) bytes"
else
    echo "⚠️ Settings file not found at $SETTINGS_FILE"
    echo "{}" > /tmp/workspace_settings.json
    echo "File not found" > /tmp/settings_metadata.txt
fi

# Create directory listing for debugging
find "$WORKSPACE_DIR/.vscode" -type f 2>/dev/null > /tmp/vscode_dir_listing.txt || echo "No .vscode directory" > /tmp/vscode_dir_listing.txt

echo "✅ Export complete"