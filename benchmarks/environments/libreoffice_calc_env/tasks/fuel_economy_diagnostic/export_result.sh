#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Fuel Economy Diagnostic Result ==="

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
else
    echo "⚠️ Warning: Could not get Calc window ID"
    # Try to find any LibreOffice window
    wid=$(wmctrl -l | grep -i 'LibreOffice' | awk '{print $1; exit}')
    if [ -n "$wid" ]; then
        su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
        sleep 0.5
    fi
fi

# Define output file path
OUTPUT_FILE="/home/ga/Documents/fuel_economy_analyzed.ods"

# Save file with Ctrl+S first (in case it's already named correctly)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1.5

# Check if ODS file already exists
if [ ! -f "$OUTPUT_FILE" ]; then
    # File not saved as ODS yet, use Save As
    echo "Using Save As to create ODS file..."
    safe_xdotool ga :1 key ctrl+shift+s
    sleep 2
    
    # Clear any existing filename and type new one
    safe_xdotool ga :1 key ctrl+a
    sleep 0.3
    safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
    sleep 0.5
    
    # Press Enter to confirm
    safe_xdotool ga :1 key Return
    sleep 1.5
    
    # Handle potential "Confirm file format" dialog (if it appears)
    safe_xdotool ga :1 key Return || true
    sleep 0.5
fi

# Wait for file to be saved
if wait_for_file "$OUTPUT_FILE" 5; then
    echo "✅ File saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE" || true
else
    echo "⚠️ Warning: ODS file not found, checking for CSV..."
    # Check if CSV was modified instead
    CSV_FILE="/home/ga/Documents/fuel_log_messy.csv"
    if [ -f "$CSV_FILE" ]; then
        echo "✅ CSV file exists: $CSV_FILE"
        ls -lh "$CSV_FILE" || true
    else
        echo "❌ Neither ODS nor CSV file found"
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

# Handle potential "Save changes?" dialog
safe_xdotool ga :1 key Return || true
sleep 0.3

echo "=== Export Complete ==="
echo "📁 Expected output files:"
echo "   - /home/ga/Documents/fuel_economy_analyzed.ods (primary)"
echo "   - /home/ga/Documents/fuel_log_messy.csv (fallback)"
echo "   - /home/ga/Documents/fuel_log_messy.ods (alternative)"