#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Utility Bill Analysis Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create realistic utility bill CSV data
cat > /home/ga/Documents/utility_bills_2023.csv << 'CSVEOF'
Bill Date,Usage (kWh),Bill Amount ($),Reading Type
2023-01-15,850,127.50,Actual
2023-02-12,920,138.00,Actual
2023-03-14,780,117.00,Estimated
2023-04-13,810,121.50,Actual
2023-05-15,890,133.50,Actual
2023-06-14,1050,157.50,Actual
2023-07-16,1180,177.00,Actual
2023-08-15,1220,183.00,Actual
2023-09-13,980,147.00,Actual
2023-10-14,840,126.00,Estimated
2023-11-12,890,133.50,Actual
2023-12-14,910,136.50,Actual
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/utility_bills_2023.csv
sudo chmod 644 /home/ga/Documents/utility_bills_2023.csv

echo "✅ Created utility_bills_2023.csv with 12 months of data"
ls -lh /home/ga/Documents/utility_bills_2023.csv

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/utility_bills_2023.csv > /tmp/calc_utility_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_utility_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
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

# Position cursor at the beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Utility Bill Analysis Task Setup Complete ==="
echo ""
echo "📊 Data Overview:"
echo "  - 12 months of utility bills (Jan-Dec 2023)"
echo "  - Varying billing periods (28-32 days)"
echo "  - 2 estimated readings (March, October)"
echo "  - Summer spike in usage (June-August)"
echo ""
echo "📝 Required Analysis:"
echo "  1. Insert column after 'Bill Date' for 'Days in Period'"
echo "  2. Calculate days between consecutive bills (e.g., =A3-A2)"
echo "  3. Insert column for 'Daily Avg (kWh/day)'"
echo "  4. Calculate daily usage (e.g., =C2/E2 where E is days column)"
echo "  5. Insert column for 'Usage Change (%)'"
echo "  6. Calculate percentage change (handle first row: N/A or formula)"
echo "  7. Apply conditional formatting to daily average column (>30 = red)"
echo "  8. Flag or highlight estimated readings"
echo ""
echo "💡 Tips:"
echo "  - Use IF() to handle first row with no previous date"
echo "  - Format percentages with % symbol"
echo "  - Format currency with $ symbol"
echo "  - Use Format → Conditional Formatting for highlighting"