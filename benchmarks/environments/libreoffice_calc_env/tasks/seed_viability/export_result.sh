#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Seed Viability Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Ensure we're on the Seed_Inventory sheet (first sheet)
echo "Ensuring correct sheet is active..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

# Save file with new name (Ctrl+Shift+S for Save As)
echo "Saving file as seed_viability_checked.ods..."
safe_xdotool ga :1 key ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/seed_viability_checked.ods"
sleep 1

# Press Enter to confirm save
safe_xdotool ga :1 key Return
sleep 2

# If file exists dialog appears (overwrite), press Enter again
safe_xdotool ga :1 key Return || true
sleep 1

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/seed_viability_checked.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/seed_viability_checked.ods"
    ls -lh /home/ga/Documents/seed_viability_checked.ods
else
    echo "⚠️ Warning: New file not found, trying to save original..."
    # Fallback: save the original file
    safe_xdotool ga :1 key ctrl+s
    sleep 1
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key ctrl+q
sleep 0.5

echo "=== Export Complete ==="