#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Environment Switcher Configuration Result ==="

WORKSPACE_DIR="/home/ga/workspace/api-service"

# Give time for any final saves
sleep 2

# Focus VSCode and save all
focus_vscode_window
{
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 1
} || {
    echo "⚠️ Failed to trigger save-all; continuing"
}

sleep 2

# Export all configuration files to /tmp for verification
echo "Exporting configuration files..."

# Export tasks.json
if [ -f "$WORKSPACE_DIR/.vscode/tasks.json" ]; then
    cp "$WORKSPACE_DIR/.vscode/tasks.json" /tmp/vscode_tasks.json
    echo "✅ Exported tasks.json"
else
    echo "⚠️ tasks.json not found"
    echo "{}" > /tmp/vscode_tasks.json
fi

# Export settings.json
if [ -f "$WORKSPACE_DIR/.vscode/settings.json" ]; then
    cp "$WORKSPACE_DIR/.vscode/settings.json" /tmp/vscode_settings.json
    echo "✅ Exported settings.json"
else
    echo "⚠️ settings.json not found"
    echo "{}" > /tmp/vscode_settings.json
fi

# Export extensions.json
if [ -f "$WORKSPACE_DIR/.vscode/extensions.json" ]; then
    cp "$WORKSPACE_DIR/.vscode/extensions.json" /tmp/vscode_extensions.json
    echo "✅ Exported extensions.json"
else
    echo "⚠️ extensions.json not found (optional)"
    echo "{}" > /tmp/vscode_extensions.json
fi

# Export switching script (try both .sh and .py)
if [ -f "$WORKSPACE_DIR/scripts/switch-env.sh" ]; then
    cp "$WORKSPACE_DIR/scripts/switch-env.sh" /tmp/switch_env_script.sh
    echo "✅ Exported switch-env.sh"
    ls -la "$WORKSPACE_DIR/scripts/switch-env.sh" > /tmp/script_permissions.txt
elif [ -f "$WORKSPACE_DIR/scripts/switch_env.py" ]; then
    cp "$WORKSPACE_DIR/scripts/switch_env.py" /tmp/switch_env_script.py
    echo "✅ Exported switch_env.py"
    ls -la "$WORKSPACE_DIR/scripts/switch_env.py" > /tmp/script_permissions.txt
else
    echo "⚠️ No switching script found"
    echo "# No script found" > /tmp/switch_env_script.sh
    echo "" > /tmp/script_permissions.txt
fi

# Export directory structure for debugging
ls -laR "$WORKSPACE_DIR/.vscode" > /tmp/vscode_dir_structure.txt 2>&1 || echo "No .vscode directory" > /tmp/vscode_dir_structure.txt
ls -la "$WORKSPACE_DIR/scripts/" > /tmp/scripts_dir_structure.txt 2>&1 || echo "No scripts directory" > /tmp/scripts_dir_structure.txt

echo "✅ Export complete"
echo "Exported files:"
echo "  - /tmp/vscode_tasks.json"
echo "  - /tmp/vscode_settings.json"
echo "  - /tmp/vscode_extensions.json"
echo "  - /tmp/switch_env_script.[sh|py]"
echo "  - /tmp/script_permissions.txt"