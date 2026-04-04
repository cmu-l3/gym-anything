#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Security Audit Result ==="

# Focus VSCode and save all files
focus_vscode_window
sleep 1

# Save all open files
echo "Saving all files..."
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

sleep 2

# Wait for audit files to be written
wait_for_file "/home/ga/workspace/security_audit/SECURITY_AUDIT.md" 3 || echo "SECURITY_AUDIT.md not found yet"
wait_for_file "/home/ga/workspace/security_audit/SECURITY_TODO.md" 3 || echo "SECURITY_TODO.md not found yet"

# Copy audit files to /tmp for verification
AUDIT_FILE="/home/ga/workspace/security_audit/SECURITY_AUDIT.md"
TODO_FILE="/home/ga/workspace/security_audit/SECURITY_TODO.md"

if [ -f "$AUDIT_FILE" ]; then
    echo "Copying SECURITY_AUDIT.md to /tmp"
    cp "$AUDIT_FILE" /tmp/security_audit.md 2>/dev/null || echo "Failed to copy audit file"
else
    echo "⚠️ SECURITY_AUDIT.md not found"
    echo "File not found" > /tmp/security_audit.md
fi

if [ -f "$TODO_FILE" ]; then
    echo "Copying SECURITY_TODO.md to /tmp"
    cp "$TODO_FILE" /tmp/security_todo.md 2>/dev/null || echo "Failed to copy TODO file"
else
    echo "⚠️ SECURITY_TODO.md not found"
    echo "File not found" > /tmp/security_todo.md
fi

echo "✅ Export complete"
echo "Files exported:"
echo "  - /tmp/security_audit.md"
echo "  - /tmp/security_todo.md"