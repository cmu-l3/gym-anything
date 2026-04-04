#!/bin/bash
# set -euo pipefail

echo "=== Setting up CSV Import Task ==="

source /workspace/scripts/task_utils.sh

# Create CSV file
cat > /home/ga/Documents/employees.csv << 'CSVEOF'
Employee ID,Name,Department,Salary,Hire Date
1001,Alice Smith,Engineering,85000,2020-01-15
1002,Bob Johnson,Marketing,72000,2019-03-20
1003,Carol Davis,Engineering,92000,2018-07-10
1004,David Wilson,Sales,68000,2021-05-05
CSVEOF

chown ga:ga /home/ga/Documents/employees.csv
echo "✅ Created employees.csv"

# Launch Calc
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore > /tmp/calc_csv_task.log 2>&1 &"
sleep 4

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_task.log
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
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


echo "=== CSV Import Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open File → Open"
echo "  2. Navigate to /home/ga/Documents/employees.csv"
echo "  3. Import CSV (accept default delimiter: comma)"
echo "  4. Format Salary column (column D) as currency"
echo "  5. Format Hire Date column (column E) as date"
echo "  6. Save as ODS: File → Save As → employees.ods"
