#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Capture Departing Knowledge Result ==="

WORKSPACE_DIR="/home/ga/workspace/payment_api"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Wait for files to be saved
sleep 2

# Copy files to /tmp for verification
if [ -f "$WORKSPACE_DIR/payment_processor.py" ]; then
    cp "$WORKSPACE_DIR/payment_processor.py" /tmp/payment_processor_result.py
    echo "✅ Copied payment_processor.py to /tmp"
fi

if [ -f "$WORKSPACE_DIR/PAYMENT_SYSTEM_GUIDE.md" ]; then
    cp "$WORKSPACE_DIR/PAYMENT_SYSTEM_GUIDE.md" /tmp/PAYMENT_SYSTEM_GUIDE_result.md
    echo "✅ Copied PAYMENT_SYSTEM_GUIDE.md to /tmp"
fi

# Create export summary
cat > /tmp/documentation_export_summary.txt << EOF
Documentation Capture Export Summary
Generated: $(date)

Files in workspace:
$(ls -lh "$WORKSPACE_DIR"/ 2>/dev/null | grep -E '\.(py|md)$' || echo "No files found")

Payment Processor Size:
$(wc -l "$WORKSPACE_DIR/payment_processor.py" 2>/dev/null || echo "File not found")

Guide Document:
$(if [ -f "$WORKSPACE_DIR/PAYMENT_SYSTEM_GUIDE.md" ]; then echo "Created"; else echo "Not found"; fi)

EOF

echo "✅ Export complete"
echo "Files exported to /tmp for verification"