#!/bin/bash
# set -euo pipefail

echo "=== Setting up Textbook Price Analyzer Task ==="

source /workspace/scripts/task_utils.sh

# Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV file with messy textbook price data
cat > /home/ga/Documents/textbook_prices.csv << 'CSVEOF'
Course,Book Title,Required Edition,Campus Bookstore,Amazon,Marketplace,Notes,Access Code Needed
CHEM 101,General Chemistry,12,145.00,128.50,110.00,Amazon: +$5 ship no access; Marketplace: 11th ed; Campus: w/ access shipping incl,Yes
BIO 200,Molecular Biology,8,210.00,189.99,175.00,Campus: w/ access shipping incl; Amazon: +$8 ship no access; Marketplace: no access +$5 ship,Yes
MATH 210,Calculus Early Transcendentals,9,180.00,165.00,,Campus: shipping incl w/ access; Amazon: +$8 ship w/ access; Marketplace: out of stock,Yes
PSYCH 101,Intro to Psychology,7,95.00,87.50,65.00,All: 7th ed no access code needed; Marketplace: used-good free ship; Amazon: +$5 ship,No
ENGL 105,Norton Anthology of Literature,5,,,125.00,Only available Marketplace; like new condition; free shipping; no access code,No
PHYS 150,University Physics,15,275.00,255.00,240.00,All: w/ access included; Amazon: Prime free ship; Campus: shipping incl; Marketplace: +$12 ship,Yes
HIST 101,Western Civilization,11,88.00,79.99,70.00,Campus: no access +shipping; Amazon: no access +$6 ship; Marketplace: 10th ed ok per professor +$4 ship,No
CS 201,Data Structures and Algorithms,4,165.00,149.00,135.00,Campus: w/ online platform shipping incl; Amazon: no platform +$7 ship; Marketplace: no platform +$5 ship,Yes
CSVEOF

chown ga:ga /home/ga/Documents/textbook_prices.csv
chmod 666 /home/ga/Documents/textbook_prices.csv
echo "✅ Created textbook_prices.csv with messy price data"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/textbook_prices.csv > /tmp/calc_textbook_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_textbook_task.log || true
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

# Move cursor to beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Textbook Price Analyzer Task Setup Complete ==="
echo ""
echo "📚 SCENARIO: College student needs to buy textbooks within $600 budget"
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "  1. Analyze the messy Notes column - shipping/access codes are inconsistent"
echo "  2. Create 'True Cost' columns for each seller (Campus, Amazon, Marketplace)"
echo "     - Add shipping if not included (assume $5 for online if not specified)"
echo "     - Add access code cost ($85) if needed but not included"
echo "  3. Create 'Best Deal' column using MIN to find lowest true cost"
echo "  4. Apply conditional formatting to highlight best deals (green)"
echo "  5. Calculate total budget (sum of best deals) and compare to $600"
echo ""
echo "💡 HINTS:"
echo "  - Use IF and SEARCH functions to parse Notes column"
echo "  - Example: =IF(ISNUMBER(SEARCH(\"shipping included\",G2)),D2,D2+5)"
echo "  - Handle blank cells with IFERROR or IF(ISBLANK(...))"
echo "  - MIN function: =MIN(I2,J2,K2) for true cost comparison"
echo ""
echo "🎯 SUCCESS CRITERIA:"
echo "  - True Cost formulas with conditional logic (IF statements)"
echo "  - Accurate calculations (spot-checked)"
echo "  - MIN function for best deal identification"
echo "  - Conditional formatting applied"
echo "  - No formula errors (#REF!, #VALUE!, etc.)"