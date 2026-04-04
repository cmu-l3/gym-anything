#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Board Strategy Review Result ==="

su - ga -c "DISPLAY=:1 scrot /tmp/task_final_screenshot.png" || true

# Save if LibreOffice still open
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
    safe_xdotool ga :1 key --delay 300 ctrl+s
    sleep 3
    # Handle any format dialog (Enter to confirm)
    safe_xdotool ga :1 key --delay 200 Return
    sleep 1
fi

if [ -f /home/ga/Documents/Presentations/board_strategy_2024.odp ]; then
    echo "ODP present: $(stat -c%s /home/ga/Documents/Presentations/board_strategy_2024.odp) bytes"
else
    echo "WARNING: ODP not found"
fi

if [ -f /home/ga/Documents/Presentations/board_strategy_2024.pptx ]; then
    echo "PPTX present: $(stat -c%s /home/ga/Documents/Presentations/board_strategy_2024.pptx) bytes"
else
    echo "PPTX not found at expected path"
fi

echo "=== Export Complete ==="
