#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Water Leak Detection Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
else
    echo "⚠️ Could not find Calc window"
fi

# Check if file already exists with correct name
if [ -f "/home/ga/Documents/water_analysis.ods" ]; then
    echo "✅ water_analysis.ods already exists, saving updates..."
    # Just save the file
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 2
else
    echo "Saving as water_analysis.ods..."
    # Save As dialog
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 2
    
    # Clear any existing filename
    safe_xdotool ga :1 key --delay 100 ctrl+a
    sleep 0.3
    
    # Type the filename
    safe_xdotool ga :1 type --delay 50 '/home/ga/Documents/water_analysis.ods'
    sleep 0.5
    
    # Press Enter to save
    safe_xdotool ga :1 key Return
    sleep 1.5
    
    # Handle any confirmation dialogs (in case file exists)
    safe_xdotool ga :1 key Return || true
    sleep 0.5
fi

# Verify file was saved
if wait_for_file "/home/ga/Documents/water_analysis.ods" 5; then
    echo "✅ File saved successfully: /home/ga/Documents/water_analysis.ods"
    ls -lh /home/ga/Documents/water_analysis.ods
else
    echo "⚠️ Warning: water_analysis.ods not found"
    # Check if still saved as CSV
    if [ -f "/home/ga/Documents/water_usage_data.csv" ]; then
        echo "ℹ️ Original CSV still exists"
    fi
    # List all files in Documents for debugging
    echo "Files in Documents directory:"
    ls -lh /home/ga/Documents/ || true
fi

# Close Calc
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1

echo "=== Export Complete ==="