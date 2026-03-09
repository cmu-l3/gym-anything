#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Investigate Failing Test Result ==="

WORKSPACE_DIR="/home/ga/workspace/payment_processor"

# Try to save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Could not save files; continuing"
}

sleep 2

# Export VSCode user settings
echo "Exporting VSCode settings..."
SETTINGS_DIR="/home/ga/.config/Code/User"
if [ -f "$SETTINGS_DIR/settings.json" ]; then
    cp "$SETTINGS_DIR/settings.json" /tmp/vscode_settings.json
    echo "✅ User settings exported"
else
    echo "{}" > /tmp/vscode_settings.json
    echo "⚠️ No user settings found"
fi

# Export workspace settings if they exist
echo "Exporting workspace settings..."
if [ -f "$WORKSPACE_DIR/.vscode/settings.json" ]; then
    cp "$WORKSPACE_DIR/.vscode/settings.json" /tmp/workspace_settings.json
    echo "✅ Workspace settings exported"
else
    echo "{}" > /tmp/workspace_settings.json
    echo "⚠️ No workspace settings found"
fi

# Export pytest cache (evidence of test execution)
echo "Exporting pytest cache..."
if [ -d "$WORKSPACE_DIR/.pytest_cache" ]; then
    # Create structure info
    find "$WORKSPACE_DIR/.pytest_cache" -type f > /tmp/pytest_cache_files.txt 2>/dev/null || echo "" > /tmp/pytest_cache_files.txt
    
    # Export specific cache files if they exist
    if [ -f "$WORKSPACE_DIR/.pytest_cache/.gitignore" ]; then
        cp "$WORKSPACE_DIR/.pytest_cache/.gitignore" /tmp/pytest_gitignore.txt
    fi
    
    if [ -d "$WORKSPACE_DIR/.pytest_cache/v" ]; then
        # Try to export cache data
        find "$WORKSPACE_DIR/.pytest_cache/v" -name "cache" -type d | head -1 | while read cachedir; do
            if [ -d "$cachedir" ]; then
                cp -r "$cachedir" /tmp/pytest_cache_data/ 2>/dev/null || true
            fi
        done
    fi
    
    echo "✅ Pytest cache data exported"
else
    echo "" > /tmp/pytest_cache_files.txt
    echo "⚠️ No pytest cache found (tests may not have been run)"
fi

# Export test discovery state
echo "Exporting test state..."
if [ -f "$WORKSPACE_DIR/.pytest_cache/v/cache/nodeids" ]; then
    cp "$WORKSPACE_DIR/.pytest_cache/v/cache/nodeids" /tmp/pytest_nodeids.txt 2>/dev/null || echo "" > /tmp/pytest_nodeids.txt
fi

# List VSCode workspace storage (indirect evidence of Test Explorer usage)
echo "Checking VSCode workspace storage..."
WORKSPACE_STORAGE="/home/ga/.config/Code/User/workspaceStorage"
if [ -d "$WORKSPACE_STORAGE" ]; then
    # Find most recently modified workspace
    find "$WORKSPACE_STORAGE" -type f -name "state.vscdb" -mmin -10 > /tmp/recent_workspace_state.txt 2>/dev/null || echo "" > /tmp/recent_workspace_state.txt
    echo "✅ Workspace storage checked"
else
    echo "" > /tmp/recent_workspace_state.txt
fi

# Export extension logs (may contain test execution info)
LOGS_DIR="/home/ga/.config/Code/logs"
if [ -d "$LOGS_DIR" ]; then
    # Get most recent log file
    RECENT_LOG=$(find "$LOGS_DIR" -name "*.log" -type f -mmin -10 | head -1)
    if [ -n "$RECENT_LOG" ]; then
        tail -100 "$RECENT_LOG" > /tmp/vscode_recent_log.txt 2>/dev/null || echo "" > /tmp/vscode_recent_log.txt
    fi
fi

# Create summary
cat > /tmp/export_summary.txt << EOF
Task: investigate_failing_test@1
Workspace: $WORKSPACE_DIR
Export timestamp: $(date)

Exported files:
- VSCode settings: $([ -f /tmp/vscode_settings.json ] && echo "Yes" || echo "No")
- Workspace settings: $([ -f /tmp/workspace_settings.json ] && echo "Yes" || echo "No")
- Pytest cache: $([ -f /tmp/pytest_cache_files.txt ] && [ -s /tmp/pytest_cache_files.txt ] && echo "Yes" || echo "No")
- Test state: $([ -f /tmp/pytest_nodeids.txt ] && echo "Yes" || echo "No")

Pytest cache files:
$(cat /tmp/pytest_cache_files.txt 2>/dev/null | head -10)
EOF

echo "✅ Export complete"
cat /tmp/export_summary.txt