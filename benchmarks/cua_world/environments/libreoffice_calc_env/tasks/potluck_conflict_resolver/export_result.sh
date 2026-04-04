#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Potluck Analysis Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Define output file
OUTPUT_FILE="/home/ga/Documents/potluck_analysis.ods"

# Try to save as ODS using Save As dialog
echo "Attempting to save as ODS..."

# Open Save As dialog (Ctrl+Shift+S)
safe_xdotool ga :1 key ctrl+shift+s
sleep 2

# Clear any existing filename and type new one
safe_xdotool ga :1 key ctrl+a
sleep 0.3
safe_xdotool ga :1 type --delay 50 "$OUTPUT_FILE"
sleep 0.5

# Press Enter to save
safe_xdotool ga :1 key Return
sleep 1.5

# Handle "already exists" dialog if it appears
safe_xdotool ga :1 key Return || true
sleep 0.5

# Check if file was saved
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Analysis saved as: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️  ODS not found, trying to save current file..."
    # Try regular save (Ctrl+S)
    safe_xdotool ga :1 key ctrl+s
    sleep 1
    
    # Check for CSV version
    if [ -f "/home/ga/Documents/potluck_signups.csv" ]; then
        echo "⚠️  CSV file exists but ODS may not be saved"
    fi
    
    # Check for ODS version of CSV name
    if [ -f "/home/ga/Documents/potluck_signups.ods" ]; then
        echo "✅ Found potluck_signups.ods"
        # Copy to expected name
        cp /home/ga/Documents/potluck_signups.ods "$OUTPUT_FILE" || true
    fi
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key ctrl+q
sleep 0.5

# Handle unsaved changes dialog if it appears
safe_xdotool ga :1 key Tab Return || true
sleep 0.3

echo "=== Export Complete ==="

# Show what files exist
echo "Available files:"
ls -lh /home/ga/Documents/*.{ods,csv} 2>/dev/null || echo "No spreadsheet files found"