#!/bin/bash
# set -euo pipefail

echo "=== Setting up Sort Data task ==="

source /workspace/scripts/task_utils.sh

# Create CSV file with sample data
cat > /home/ga/Documents/sort_data_input.csv << 'EOF'
Name,Score
Alice,85
Bob,72
Charlie,95
David,63
Eve,88
EOF

chown ga:ga /home/ga/Documents/sort_data_input.csv

# Open the CSV file in LibreOffice Calc
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/sort_data_input.csv > /tmp/libreoffice_sort.log 2>&1 &"
sleep 5

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_task.log
    # exit 1
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 120; then
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


echo "=== Sort Data task setup completed ==="
echo "📋 Task: Sort the data by the 'Score' column in ascending order"
echo "💡 Hint: Select data range, then Data → Sort"
