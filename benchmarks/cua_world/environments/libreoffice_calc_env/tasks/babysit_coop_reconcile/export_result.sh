#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Babysitting Co-op Reconciliation Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Save file as ODS (Ctrl+S will save as ODS since we opened CSV)
echo "Saving file..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 1

# If it prompts to confirm ODS format, press Enter
safe_xdotool ga :1 key --delay 200 Return
sleep 1

# Check if ODS file exists, otherwise save explicitly as ODS
ODS_FILE="/home/ga/Documents/babysit_coop_transactions.ods"
if [ ! -f "$ODS_FILE" ]; then
    echo "ODS not found, trying Save As..."
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 2
    
    # Clear filename field and type new name
    safe_xdotool ga :1 key --delay 200 ctrl+a
    sleep 0.3
    safe_xdotool ga :1 type --delay 50 "/home/ga/Documents/babysit_coop_reconciled.ods"
    sleep 0.5
    
    # Press Enter to save
    safe_xdotool ga :1 key --delay 200 Return
    sleep 1
fi

# Wait for file to be saved
if wait_for_file "/home/ga/Documents/babysit_coop_transactions.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/babysit_coop_transactions.ods"
    ls -lh /home/ga/Documents/babysit_coop_transactions.ods
elif wait_for_file "/home/ga/Documents/babysit_coop_reconciled.ods" 5; then
    echo "✅ File saved: /home/ga/Documents/babysit_coop_reconciled.ods"
    ls -lh /home/ga/Documents/babysit_coop_reconciled.ods
else
    echo "⚠️ Warning: File not found or not recently modified"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="