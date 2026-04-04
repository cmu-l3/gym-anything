#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Accessibility Audit Result ==="

WORKSPACE_DIR="/home/ga/workspace/accessibility_audit"

# Try to save any open files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save command; continuing"
}

sleep 2

# Check if audit report exists
if [ -f "$WORKSPACE_DIR/ACCESSIBILITY_AUDIT.md" ]; then
    echo "✅ Audit report found"
    echo "Report preview:"
    head -n 20 "$WORKSPACE_DIR/ACCESSIBILITY_AUDIT.md"
else
    echo "⚠️ Audit report not found at $WORKSPACE_DIR/ACCESSIBILITY_AUDIT.md"
fi

# Export component files and report to /tmp for verifier
mkdir -p /tmp/accessibility_audit_export
cp -r "$WORKSPACE_DIR/src" /tmp/accessibility_audit_export/ 2>/dev/null || true
cp "$WORKSPACE_DIR/ACCESSIBILITY_AUDIT.md" /tmp/accessibility_audit_export/ 2>/dev/null || true
cp "$WORKSPACE_DIR/.violations_key.json" /tmp/accessibility_audit_export/ 2>/dev/null || true

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"