#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Plant Propagation Analyzer Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file with specific name
OUTPUT_FILE="/home/ga/Documents/propagation_analysis.ods"

# Use Save As to ensure ODS format
echo "Saving file as ODS..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing text and type new filename
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# If file exists dialog appears, confirm overwrite
safe_xdotool ga :1 key Return || true
sleep 0.5

# Verify file was saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Warning: File not found at expected location"
    # Try alternate locations
    if [ -f "/home/ga/Documents/propagation_log.ods" ]; then
        echo "📁 Found: propagation_log.ods"
        # Copy to expected name
        sudo -u ga cp /home/ga/Documents/propagation_log.ods "$OUTPUT_FILE" || true
    fi
fi

# Close Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Force close if still running
if pgrep -f "soffice.*calc" > /dev/null; then
    echo "Force closing Calc..."
    pkill -f "soffice.*calc" || true
    sleep 0.5
fi

echo "=== Export Complete ==="