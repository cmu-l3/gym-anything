#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Accessibility Violations Result ==="

WORKSPACE_DIR="/home/ga/workspace/accessibility-fixes"
COMPONENT_FILE="$WORKSPACE_DIR/src/components/DataTable.jsx"

# Focus VSCode and save
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Wait for file to be saved
sleep 2

# Verify file exists
if [ -f "$COMPONENT_FILE" ]; then
    echo "✓ Component file exists: $COMPONENT_FILE"
    
    # Copy to /tmp for verifier
    cp "$COMPONENT_FILE" /tmp/DataTable.jsx
    echo "✓ Copied DataTable.jsx to /tmp for verification"
    
    # Show file size
    ls -lh "$COMPONENT_FILE"
else
    echo "⚠️ Warning: Component file not found at $COMPONENT_FILE"
    touch /tmp/DataTable.jsx
fi

# Also copy audit report for reference
cp "$WORKSPACE_DIR/audit_report.md" /tmp/audit_report.md 2>/dev/null || true

# Take screenshot for debugging
su - ga -c "DISPLAY=:1 import -window root /tmp/accessibility_task_screenshot.png" 2>/dev/null || true

echo "✅ Export complete"
echo "Results location: /tmp/DataTable.jsx"