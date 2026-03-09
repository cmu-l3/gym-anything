#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Print Layout Crisis Result ==="

# Focus Calc window
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Save file (Ctrl+S)
echo "Saving file with print configuration..."
safe_xdotool ga :1 key --delay 200 ctrl+s

# Wait for file to be saved (check modification time)
sleep 2

# Create results directory if it doesn't exist
sudo -u ga mkdir -p /home/ga/Documents/results

# Copy to results directory for verification
if [ -f /home/ga/Documents/inventory_to_print.ods ]; then
    sudo cp /home/ga/Documents/inventory_to_print.ods /home/ga/Documents/results/print_optimized_inventory.ods
    sudo chown ga:ga /home/ga/Documents/results/print_optimized_inventory.ods
    echo "✅ File saved: /home/ga/Documents/results/print_optimized_inventory.ods"
    ls -lh /home/ga/Documents/results/print_optimized_inventory.ods
else
    echo "⚠️ Warning: inventory_to_print.ods not found"
fi

# Close Calc (Ctrl+Q)
echo "Closing LibreOffice Calc..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 0.5

echo "=== Export Complete ==="