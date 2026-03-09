#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Workspace Recovery Result ==="

WORKSPACE_DIR="/home/ga/workspace/recovery_task"
SETTINGS_DIR="/home/ga/.config/Code/User"

# Give a moment for any saves to complete
sleep 2

# Try to save any open files
focus_vscode_window 2>&1 || true
su - ga -c "DISPLAY=:1 xdotool key ctrl+shift+s" 2>&1 || true
sleep 1

# Export settings files
echo "Exporting settings files..."
if [ -f "$SETTINGS_DIR/settings.json" ]; then
    cp "$SETTINGS_DIR/settings.json" /tmp/user_settings.json 2>&1 || echo "{}" > /tmp/user_settings.json
else
    echo "{}" > /tmp/user_settings.json
fi

if [ -f "$WORKSPACE_DIR/.vscode/settings.json" ]; then
    cp "$WORKSPACE_DIR/.vscode/settings.json" /tmp/workspace_settings.json 2>&1 || echo "{}" > /tmp/workspace_settings.json
else
    echo "{}" > /tmp/workspace_settings.json
fi

# Export extensions list
echo "Exporting extensions status..."
su - ga -c "DISPLAY=:1 code --list-extensions > /tmp/extensions_list.txt 2>&1" || echo "" > /tmp/extensions_list.txt
ls -la /home/ga/.vscode/extensions/ > /tmp/extensions_dir.txt 2>&1 || echo "No extensions dir" > /tmp/extensions_dir.txt

# Export any recovery documentation
if [ -f "$WORKSPACE_DIR/RECOVERY_LOG.md" ]; then
    cp "$WORKSPACE_DIR/RECOVERY_LOG.md" /tmp/recovery_log.md
    echo "✅ Recovery log found"
else
    echo "⚠️  No recovery log found"
    echo "" > /tmp/recovery_log.md
fi

# Export workspace files list (to verify no data loss)
ls -laR "$WORKSPACE_DIR" > /tmp/workspace_files.txt 2>&1 || echo "" > /tmp/workspace_files.txt

# Try to get VSCode process status
ps aux | grep -i "code\|extension" | grep -v grep > /tmp/vscode_processes.txt 2>&1 || echo "" > /tmp/vscode_processes.txt

# Check for Python language server
ps aux | grep -i "pylance\|python" | grep -v grep > /tmp/python_processes.txt 2>&1 || echo "" > /tmp/python_processes.txt

# Export recent VSCode logs if available
LOG_DIR="/home/ga/.config/Code/logs"
if [ -d "$LOG_DIR" ]; then
    # Find most recent log directory
    RECENT_LOG=$(ls -td "$LOG_DIR"/* 2>/dev/null | head -1)
    if [ -n "$RECENT_LOG" ] && [ -d "$RECENT_LOG" ]; then
        # Export extension host log
        if [ -f "$RECENT_LOG/exthost1/exthost.log" ]; then
            tail -n 100 "$RECENT_LOG/exthost1/exthost.log" > /tmp/exthost.log 2>&1
        fi
        
        # Export main log
        if [ -f "$RECENT_LOG/main.log" ]; then
            tail -n 100 "$RECENT_LOG/main.log" > /tmp/main.log 2>&1
        fi
    fi
fi

# Create a summary file
cat > /tmp/recovery_summary.txt << EOF
=== Workspace Recovery Summary ===
Timestamp: $(date)

User Settings: $SETTINGS_DIR/settings.json
Workspace Settings: $WORKSPACE_DIR/.vscode/settings.json
Recovery Log: $WORKSPACE_DIR/RECOVERY_LOG.md

Extensions Count: $(wc -l < /tmp/extensions_list.txt)
Python Processes: $(wc -l < /tmp/python_processes.txt)

EOF

echo "✅ Export complete"
echo "Results exported to /tmp/"