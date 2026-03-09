#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Course Conflict Checker Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as ODS format (Ctrl+S)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Additional save to ensure ODS format
# Try Save As to explicitly save as ODS
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Type the output filename
OUTPUT_FILE="/home/ga/Documents/course_conflicts.ods"
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# Handle any "file exists" or format confirmation dialogs
safe_xdotool ga :1 key Return || true
sleep 0.5

# Wait for file to be saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE" || true
else
    # Fallback: check if CSV was modified
    if [ -f "/home/ga/Documents/fall_2025_courses.csv" ]; then
        echo "⚠️ ODS not found, but CSV exists: /home/ga/Documents/fall_2025_courses.csv"
        ls -lh /home/ga/Documents/fall_2025_courses.csv || true
    else
        echo "⚠️ Warning: Output file not found"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Force close if still running
if pgrep -f "soffice.*calc" > /dev/null 2>&1; then
    echo "Force closing LibreOffice..."
    pkill -f "soffice.*calc" || true
    sleep 1
fi

echo "=== Export Complete ==="