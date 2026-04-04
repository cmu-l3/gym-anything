#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Offline Mode Result ==="

# Give VSCode time to save settings
sleep 2

# Export User settings.json
USER_SETTINGS="/home/ga/.config/Code/User/settings.json"
if [ -f "$USER_SETTINGS" ]; then
    echo "Exporting User settings.json..."
    cp "$USER_SETTINGS" /tmp/user_settings.json 2>&1 || echo "{}" > /tmp/user_settings.json
    echo "✅ User settings exported"
else
    echo "⚠️ User settings not found at $USER_SETTINGS"
    echo "{}" > /tmp/user_settings.json
fi

# Export Workspace settings.json if it exists
WORKSPACE_SETTINGS="/home/ga/workspace/offline_project/.vscode/settings.json"
if [ -f "$WORKSPACE_SETTINGS" ]; then
    echo "Exporting Workspace settings.json..."
    cp "$WORKSPACE_SETTINGS" /tmp/workspace_settings.json 2>&1 || echo "{}" > /tmp/workspace_settings.json
    echo "✅ Workspace settings exported"
else
    echo "⚠️ Workspace settings not found (this is OK, User settings are sufficient)"
    echo "{}" > /tmp/workspace_settings.json
fi

# Export combined view of settings for debugging
echo "Creating combined settings snapshot..."
cat > /tmp/settings_info.txt << 'EOF'
=== User Settings Path ===
/home/ga/.config/Code/User/settings.json

=== Workspace Settings Path ===
/home/ga/workspace/offline_project/.vscode/settings.json

=== Settings Export Complete ===
EOF

echo "✅ Settings export complete"
echo "User settings: $USER_SETTINGS"
echo "Workspace settings: $WORKSPACE_SETTINGS (optional)"

# Display current settings for debugging
if [ -f "$USER_SETTINGS" ]; then
    echo ""
    echo "Current User settings:"
    cat "$USER_SETTINGS" | grep -E "(update|telemetry|extensions|git|autoSave)" || echo "No offline settings found"
fi