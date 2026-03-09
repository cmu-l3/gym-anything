#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Board Game Value Analyzer Result ==="

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file as board_game_analysis.ods using Save As
echo "Saving file as board_game_analysis.ods..."

# Use Save As (Ctrl+Shift+S)
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key --delay 100 ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/board_game_analysis.ods'
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1

# Handle potential overwrite dialog
safe_xdotool ga :1 key Return || true
sleep 1

# Also save original file (Ctrl+S) as backup
echo "Saving original file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# Verify file exists
if [ -f "/home/ga/Documents/board_game_analysis.ods" ]; then
    echo "✅ File saved: /home/ga/Documents/board_game_analysis.ods"
    ls -lh /home/ga/Documents/board_game_analysis.ods
elif [ -f "/home/ga/Documents/board_game_collection.ods" ]; then
    echo "⚠️ Analysis file not found, but original exists: board_game_collection.ods"
    ls -lh /home/ga/Documents/board_game_collection.ods
else
    echo "⚠️ Warning: Neither file found"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="