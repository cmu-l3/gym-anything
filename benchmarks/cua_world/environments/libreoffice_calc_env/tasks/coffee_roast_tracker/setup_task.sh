#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Coffee Roast Freshness Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Calculate dates relative to today for realistic freshness distribution
# We'll create roasts spanning the last 30 days
TODAY=$(date +%Y-%m-%d)
DATE_25_DAYS_AGO=$(date -d "25 days ago" +%Y-%m-%d)
DATE_20_DAYS_AGO=$(date -d "20 days ago" +%Y-%m-%d)
DATE_18_DAYS_AGO=$(date -d "18 days ago" +%Y-%m-%d)
DATE_15_DAYS_AGO=$(date -d "15 days ago" +%Y-%m-%d)
DATE_12_DAYS_AGO=$(date -d "12 days ago" +%Y-%m-%d)
DATE_10_DAYS_AGO=$(date -d "10 days ago" +%Y-%m-%d)
DATE_8_DAYS_AGO=$(date -d "8 days ago" +%Y-%m-%d)
DATE_6_DAYS_AGO=$(date -d "6 days ago" +%Y-%m-%d)
DATE_3_DAYS_AGO=$(date -d "3 days ago" +%Y-%m-%d)
DATE_2_DAYS_AGO=$(date -d "2 days ago" +%Y-%m-%d)
DATE_1_DAY_AGO=$(date -d "1 day ago" +%Y-%m-%d)
DATE_TODAY=$(date +%Y-%m-%d)

# Create CSV with coffee roast log data
cat > /home/ga/Documents/coffee_roast_log.csv << EOF
Bean Name,Origin,Roast Date,Weight (g),Roast Level
Ethiopia Yirgacheffe,Ethiopia,$DATE_15_DAYS_AGO,250,Light
Colombia Huila,Colombia,$DATE_8_DAYS_AGO,300,Medium
Kenya AA,Kenya,$DATE_12_DAYS_AGO,250,Medium-Light
Guatemala Antigua,Guatemala,$DATE_20_DAYS_AGO,300,Medium
Brazil Santos,Brazil,$DATE_3_DAYS_AGO,350,Medium-Dark
Costa Rica Tarrazu,Costa Rica,$DATE_10_DAYS_AGO,250,Medium
Sumatra Mandheling,Indonesia,$DATE_25_DAYS_AGO,300,Dark
Peru Organic,Peru,$DATE_2_DAYS_AGO,250,Medium
Rwanda Bourbon,Rwanda,$DATE_18_DAYS_AGO,250,Light
Honduras SHG,Honduras,$DATE_6_DAYS_AGO,300,Medium
Papua New Guinea,Papua New Guinea,$DATE_1_DAY_AGO,250,Medium-Light
Yemen Mokha,Yemen,$DATE_TODAY,200,Light
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/coffee_roast_log.csv
sudo chmod 666 /home/ga/Documents/coffee_roast_log.csv

echo "✅ Created coffee roast log with dates spanning last 25 days"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc with roast log..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/coffee_roast_log.csv > /tmp/calc_coffee_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_coffee_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop
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

# Move cursor to cell F1 to prepare for Days Since Roast column
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to column F (Right arrow 5 times from A1)
safe_xdotool ga :1 key Right Right Right Right Right
sleep 0.2

echo "=== Coffee Roast Freshness Tracker Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Add 'Days Since Roast' header in column F"
echo "  2. In F2, enter formula: =TODAY()-C2"
echo "  3. Copy formula down to all data rows"
echo "  4. Apply conditional formatting to F column:"
echo "     • 0-4 days: Yellow (too fresh)"
echo "     • 5-14 days: Green (peak window)"
echo "     • 15-21 days: Orange (good)"
echo "     • 22+ days: Red (stale)"
echo "  5. Sort by Roast Date (column C) - oldest first"
echo ""
echo "💡 Hint: This helps identify which beans are in optimal brewing window!"