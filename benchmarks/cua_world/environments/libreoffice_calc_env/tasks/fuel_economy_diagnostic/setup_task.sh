#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Fuel Economy Diagnostic Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy fuel log CSV with realistic data quality issues
cat > /home/ga/Documents/fuel_log_messy.csv << 'CSVEOF'
Date,Miles Driven,Gallons Filled,Trip Type,Weather,AC Usage,Cargo Load
2024-01-15,342,12.1,Mixed,Cold,NO,Light
2024-01-22,298 mi,11.8 gal,City,COLD,no,Light
2024-01-29,385,13.2,Highway,Cold,No,Light
2024-02-05,276,10.9,City,Cold,NO,Medium
2024-02-12,318,11.2,Mixed,Mild,yes,Light
2024-02-19,405,13.8,Highway,Mild,YES,Light
2024-02-26,245 miles,9.8,City,Warm,Yes,Heavy
2024-03-04,356,12.4,Mixed,Warm,YES,Medium
2024-03-11,289,11.1,City,Hot,On,Light
2024-03-11,289,11.1,City,Hot,On,Light
2024-03-18,412,14.2,Highway,Hot,yes,Light
2024-03-25,267,10.5 gallons,City,Hot,YES,Medium
2024-04-01,338,11.9,Mixed,hot,On,Heavy
2024-04-08,295,11.4,City,Warm,YES,Light
2024-04-15,398,13.5,Highway,Warm,No,Light
2024-04-22,312 mi,12.8 gal,Mixed,Hot,yes,Medium
2024-04-29,278,10.9,City,Hot,On,Light
2024-05-06,423,14.8,Highway,Hot,NO,Light
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/fuel_log_messy.csv
sudo chmod 644 /home/ga/Documents/fuel_log_messy.csv

echo "✅ Created messy fuel log CSV with 18 entries (including 1 duplicate)"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with fuel_log_messy.csv..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/fuel_log_messy.csv > /tmp/calc_fuel_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_fuel_task.log || true
    # Don't exit, continue for robustness
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue for robustness
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
        echo "✅ Calc window focused"
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
else
    echo "⚠️ Warning: Could not get Calc window ID"
fi

# Position cursor at A1
echo "Positioning cursor at A1..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo ""
echo "=== Fuel Economy Diagnostic Task Setup Complete ==="
echo ""
echo "📋 TASK OVERVIEW:"
echo "   A car owner's fuel economy dropped from 32 MPG baseline."
echo "   The fill-up log data is messy and needs analysis."
echo ""
echo "🎯 YOUR GOALS:"
echo "   1. Clean data: Remove text from Miles ('298 mi' → 298) and Gallons columns ('11.8 gal' → 11.8)"
echo "   2. Standardize Weather: Make consistent (Cold, Warm, Hot, Mild - proper capitalization)"
echo "   3. Standardize AC Usage: Make consistent (Yes or No only)"
echo "   4. Find and delete duplicate entry (March 11 appears twice)"
echo "   5. Add 'MPG Calculated' column with formula: =Miles/Gallons"
echo "   6. Add 'Performance' column with IF formula: Good (≥32), Fair (29-31), Poor (<29)"
echo "   7. Apply conditional formatting to MPG column (highlight values < 30)"
echo "   8. Save the cleaned file"
echo ""
echo "💡 TIPS:"
echo "   - Use Find & Replace (Ctrl+H) to clean text from numbers"
echo "   - Sort by Date to spot the duplicate entry"
echo "   - Create formulas in first data row, then copy down"
echo "   - Format → Conditional Formatting → Cell value less than 30"
echo ""
echo "⏱️  Time limit: 180 seconds (3 minutes)"
echo ""