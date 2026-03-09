#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Utility Bill Analysis Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS (Ctrl+Shift+S for Save As, or just Ctrl+S if already ODS)
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Type the output filename
OUTPUT_FILE="/home/ga/Documents/utility_analysis.ods"
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to confirm filename
safe_xdotool ga :1 key Return
sleep 1.5

# If there's a format confirmation dialog, press Enter again
safe_xdotool ga :1 key Return
sleep 1

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️  Warning: File not found at expected location"
    echo "Attempting regular save (Ctrl+S)..."
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 2
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="