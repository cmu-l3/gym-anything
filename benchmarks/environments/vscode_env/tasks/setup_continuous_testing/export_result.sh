#!/bin/bash
# set -euo pipefail

echo "=== Exporting Continuous Testing Setup Result ==="

USER_SETTINGS="/home/ga/.config/Code/User/settings.json"
WORKSPACE_SETTINGS="/home/ga/workspace/data_processor/.vscode/settings.json"
EXPORT_DIR="/tmp/testing_export"

mkdir -p "$EXPORT_DIR"

# Export user settings
if [ -f "$USER_SETTINGS" ]; then
    echo "Exporting user settings..."
    cp "$USER_SETTINGS" "$EXPORT_DIR/user_settings.json"
    echo "✅ User settings exported"
else
    echo "⚠️ User settings not found at $USER_SETTINGS"
    echo "{}" > "$EXPORT_DIR/user_settings.json"
fi

# Export workspace settings if they exist
if [ -f "$WORKSPACE_SETTINGS" ]; then
    echo "Exporting workspace settings..."
    cp "$WORKSPACE_SETTINGS" "$EXPORT_DIR/workspace_settings.json"
    echo "✅ Workspace settings exported"
else
    echo "ℹ️ Workspace settings not found (optional)"
    echo "{}" > "$EXPORT_DIR/workspace_settings.json"
fi

# List installed Python extensions
echo "Exporting extension info..."
su - ga -c "DISPLAY=:1 code --list-extensions | grep -i python" > "$EXPORT_DIR/python_extensions.txt" 2>&1 || echo "" > "$EXPORT_DIR/python_extensions.txt"

echo "✅ Export complete"
echo "Export directory: $EXPORT_DIR"
ls -la "$EXPORT_DIR"