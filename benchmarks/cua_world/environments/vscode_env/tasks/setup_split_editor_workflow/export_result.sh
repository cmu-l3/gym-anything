#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Split-Editor Workflow Result ==="

WORKSPACE_DIR="/home/ga/workspace/contact_form"

# Ensure VSCode has saved all files by triggering save-all
focus_vscode_window
{
    echo "Attempting to save all files..."
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to trigger save commands; continuing"
}

# Wait for files to be written
sleep 2

# Verify files exist
if [ -f "$WORKSPACE_DIR/form.html" ]; then
    echo "✅ form.html exists"
else
    echo "⚠️ form.html not found"
fi

if [ -f "$WORKSPACE_DIR/styles.css" ]; then
    echo "✅ styles.css exists"
else
    echo "⚠️ styles.css not found"
fi

if [ -f "$WORKSPACE_DIR/script.js" ]; then
    echo "✅ script.js exists"
else
    echo "⚠️ script.js not found"
fi

echo ""
echo "=== Export Complete ==="
echo "Files location: $WORKSPACE_DIR"
echo "Verifier will check:"
echo "  - Consistent naming across HTML/CSS/JS"
echo "  - CSS includes .contact-form, #submitBtn, #submitBtn:hover"
echo "  - JavaScript targets new 'submitBtn' ID"
echo "  - Old identifiers ('old-form', 'oldSubmit') removed"