#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting License Audit Result ==="

PROJECT_DIR="/home/ga/workspace/license_audit_project"
REPORT_FILE="$PROJECT_DIR/LICENSE_AUDIT_REPORT.md"

# Wait a moment for any pending file saves
sleep 2

# Try to save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Could not send save command to VSCode"
}

# Wait for report file to be written
sleep 2

# Copy the audit report to /tmp for verification
if [ -f "$REPORT_FILE" ]; then
    echo "Copying audit report to /tmp..."
    cp "$REPORT_FILE" /tmp/LICENSE_AUDIT_REPORT.md
    echo "✅ Audit report exported successfully"
    
    # Show first few lines for debugging
    echo ""
    echo "=== Report Preview ==="
    head -n 20 "$REPORT_FILE"
    echo "=== End Preview ==="
else
    echo "⚠️ Audit report not found at $REPORT_FILE"
    echo "" > /tmp/LICENSE_AUDIT_REPORT.md
fi

# Export package.json for reference
if [ -f "$PROJECT_DIR/package.json" ]; then
    cp "$PROJECT_DIR/package.json" /tmp/audit_package.json
fi

# Export node_modules listing for verification
if [ -d "$PROJECT_DIR/node_modules" ]; then
    ls -la "$PROJECT_DIR/node_modules" > /tmp/node_modules_list.txt 2>&1
fi

echo "✅ Export complete"
echo "Report location: $REPORT_FILE"