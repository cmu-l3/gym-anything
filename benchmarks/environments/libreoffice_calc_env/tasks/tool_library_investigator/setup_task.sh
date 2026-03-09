#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Tool Library Investigator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy CSV with mixed date formats and missing data
cat > /home/ga/Documents/tool_library_log.csv << 'CSVEOF'
Borrower,Tool,Borrow_Date,Return_Date,Notes
Sarah Miller,Pressure Washer,5/3/24,5/7/2024,Cleaned driveway
Tom Chen,Chainsaw,May 5, 2024,2024-05-08,Tree trimming
Mike Roberts,Pressure Washer,5-10-2024,,Said he never borrowed it
Jessica Lee,Pressure Washer,2024-05-14,May 18, 2024,House siding project
Tom Chen,Pressure Washer,5/19/24,5-22-2024,Returned broken - nozzle damaged
David Park,Lawn Aerator,May 15, 2024,2024-05-16,Spring maintenance
Sarah Miller,Hedge Trimmer,5/1/24,May 3, 2024,Yard work
Kevin Brown,Ladder,2024-05-12,5-16-2024,Gutter cleaning
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/tool_library_log.csv
sudo chmod 666 /home/ga/Documents/tool_library_log.csv

echo "✅ Created tool_library_log.csv with messy data"
echo "   - Mixed date formats: 5/3/24, May 15, 2024, 2024-05-18"
echo "   - Missing return date: Mike Roberts (row 4)"
echo "   - Damage period: May 15-20, 2024"
echo "   - Repair cost to split: $85.00"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/tool_library_log.csv > /tmp/calc_tool_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_tool_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of screen to select desktop
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Tool Library Investigator Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "   Neighborhood tool library dispute - pressure washer returned broken"
echo "   Repair cost: $85.00 | Damage period: May 15-20, 2024"
echo ""
echo "📝 YOUR TASKS:"
echo "   1. Standardize all date formats (columns C & D)"
echo "   2. Infer missing return dates (Mike Roberts has blank return)"
echo "   3. Calculate possession periods (days)"
echo "   4. Identify who had tool during May 15-20, 2024"
echo "   5. Calculate fair cost split ($85 total)"
echo "   6. Apply conditional formatting to highlight:"
echo "      - Borrowers during damage period (red/orange)"
echo "      - Missing/problematic data (yellow)"
echo "      - Cost amounts (currency format)"
echo ""
echo "💡 HINTS:"
echo "   - Use DATE() or DATEVALUE() functions for date conversion"
echo "   - Mike's return date = Jessica's borrow date - 1 day"
echo "   - Use IF(AND(...)) to check date overlaps"
echo "   - Cost split: (overlap_days / total_overlap_days) × 85"
echo ""