#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Recipe Optimizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the messy cookie experiments CSV data
cat > /home/ga/Documents/cookie_experiments.csv << 'CSVEOF'
Experiment,Butter_Type,Sugar_Type,Chocolate_Type,Taste_Rating,Texture_Rating,Cost_USD,Ease_Rating
1,butter,white sugar,chips,8,7,3.50,4
2,Butter,brown sugar,Chips,9,8,4.00,4
3,margarine,white sugar,chunks,6,5,2.50,5
4,butter ,coconut sugar,chips,7,9,5.50,3
5,coconut oil,white sugar,bar chopped,4,6,4.50,2
6,Butter,White Sugar,chips,8,8,3.50,5
7,margarine,brown sugar,Chunks,5,4,3.00,5
8,butter,honey,chips,6,7,6.00,2
9,Butter,brown sugar,chips,4.5,4,4.00,4
10,coconut oil,coconut sugar,bar chopped,3,5,7.00,1
11,butter,white sugar,Chips,9,9,3.50,5
12,Margarine ,white sugar,chunks,6,6,2.50,4
13,butter,brown sugar,bar chopped,8,7,4.50,3
14,Butter,white sugar,chunks,7,8,4.00,4
15,margarine,coconut sugar,chips,5,5,5.00,4
16,butter,White Sugar,chips,9,8,3.50,5
17,coconut oil,brown sugar,Chunks,4,4,5.50,3
18,butter,brown sugar,Chips,8,9,4.00,4
19,Butter,white sugar,bar chopped,7,7,4.50,3
20,margarine,white sugar,chips,6,6,2.50,5
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/cookie_experiments.csv
sudo chmod 666 /home/ga/Documents/cookie_experiments.csv

echo "✅ Created cookie_experiments.csv with 20 messy experiments"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with cookie experiment data..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/cookie_experiments.csv > /tmp/calc_recipe_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_recipe_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
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

# Move cursor to beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Recipe Optimizer Task Setup Complete ==="
echo ""
echo "📊 Task: Optimize Cookie Recipe Experiments"
echo ""
echo "📝 Instructions:"
echo "  1. Clean Data:"
echo "     - Standardize Butter_Type, Sugar_Type, Chocolate_Type (fix capitalization & spaces)"
echo "     - Create new columns: Butter_Clean, Sugar_Clean, Chocolate_Clean"
echo "  2. Normalize Ratings (to 0-10 scale):"
echo "     - Taste_Rating: some are 1-5 (double them), some are 1-10"
echo "     - Create: Taste_Norm, Texture_Norm, Ease_Norm, Cost_Norm"
echo "  3. Create Composite Score:"
echo "     - Formula: (Taste*0.4 + Texture*0.3 + Ease*0.2 + (10-Cost_Norm)*0.1)"
echo "     - Add column: Composite_Score"
echo "  4. Identify Top 3:"
echo "     - Sort by Composite_Score (descending) OR mark top 3"
echo "  5. Flag Invalid Data:"
echo "     - Add column: Valid (TRUE/FALSE for quality checks)"
echo "  6. Category Analysis:"
echo "     - Calculate average scores by ingredient type"
echo "  7. Save as: cookie_analysis.ods"
echo ""
echo "💡 Data Issues to Fix:"
echo "   - 'butter' vs 'Butter' vs 'butter ' (trailing space)"
echo "   - Mixed 1-5 and 1-10 rating scales"
echo "   - Inconsistent capitalization throughout"