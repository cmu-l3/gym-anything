#!/bin/bash
# set -euo pipefail

echo "=== Setting up Create Chart task ==="

source /workspace/scripts/task_utils.sh

# Create CSV with sales data
cat > /home/ga/Documents/sales_data.csv << 'EOF'
Month,Sales
January,12500
February,15200
March,14800
April,16300
May,17900
June,18500
EOF

chown ga:ga /home/ga/Documents/sales_data.csv

# Open in Calc
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/sales_data.csv > /tmp/libreoffice_chart.log 2>&1 &"
sleep 5

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_task.log
    # exit 1
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # exit 1
fi


# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

echo "=== Create Chart task setup completed ==="
echo "📋 Task: Create a bar or column chart from the sales data"
echo "💡 Hint: Select data range, then Insert → Chart"
