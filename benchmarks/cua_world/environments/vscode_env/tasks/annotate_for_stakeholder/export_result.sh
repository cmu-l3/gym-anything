#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Annotate for Stakeholder Result ==="

# Focus VSCode and save
focus_vscode_window
sleep 0.5

# Ensure file is saved
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save command; continuing"
}

sleep 2

# Wait for file to be written
wait_for_file "/home/ga/workspace/pricing_service/src/pricing.py" 5

# Copy modified file to /tmp for easier verification access
sudo -u ga cp /home/ga/workspace/pricing_service/src/pricing.py /tmp/pricing_annotated.py 2>&1 || true

echo "✅ Export complete"
echo "Modified file: /home/ga/workspace/pricing_service/src/pricing.py"
echo "Backup copy: /tmp/pricing_annotated.py"

# Show comment count for debugging
echo "Comment lines in file:"
grep -c "^[[:space:]]*#" /home/ga/workspace/pricing_service/src/pricing.py || echo "0"