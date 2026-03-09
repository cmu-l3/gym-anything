#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Diagnose Cross-Platform Bug Result ==="

WORKSPACE_DIR="/home/ga/workspace/webapp"
REPORT_FILE="$WORKSPACE_DIR/DIAGNOSTIC_REPORT.md"

# Give agent time to save any open files
sleep 2

# Try to save current file in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save file in VSCode; continuing"
}

# Check if diagnostic report exists
if [ -f "$REPORT_FILE" ]; then
    echo "✅ Diagnostic report found at $REPORT_FILE"
    
    # Copy to /tmp for verifier
    cp "$REPORT_FILE" /tmp/diagnostic_report.md 2>/dev/null || true
    
    # Show preview
    echo ""
    echo "=== Report Preview (first 25 lines) ==="
    head -n 25 "$REPORT_FILE"
    echo ""
    echo "=== Report Statistics ==="
    wc -l "$REPORT_FILE"
    echo ""
else
    echo "❌ Diagnostic report not found at $REPORT_FILE"
    echo "" > /tmp/diagnostic_report.md
fi

# Export file structure for debugging
echo "=== File Structure ==="
ls -la "$WORKSPACE_DIR/static/"
ls -la "$WORKSPACE_DIR/static/css/" 2>/dev/null || echo "css directory check"
ls -la "$WORKSPACE_DIR/models.py" 2>/dev/null || echo "models.py check"

echo "✅ Export complete"