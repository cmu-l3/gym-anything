#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Software TOS Conspicuous Formatting Result ==="

# Bring Calligra Words to foreground if running
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
    sleep 0.5
fi

# Take final screenshot showing end state
take_screenshot /tmp/calligra_software_tos_conspicuous_formatting_post_task.png

# Verify file exists and log its status
if [ -f "/home/ga/Documents/saas_terms_of_service.odt" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" /home/ga/Documents/saas_terms_of_service.odt || true
else
    echo "Warning: /home/ga/Documents/saas_terms_of_service.odt is missing"
fi

# Gracefully attempt to close Calligra to ensure buffers are flushed
# But do NOT force save; we want to grade the agent's actual manual saving
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

# Kill remaining processes
kill_calligra_processes

echo "=== Export Complete ==="