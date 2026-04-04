#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Judge Score Normalization Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with pie competition scores showing clear judge bias
cat > /home/ga/Documents/pie_competition.csv << 'CSVEOF'
Pie Name,Judge 1,Judge 2,Judge 3,Judge 4
Apple Classic,7,5,8,9
Cherry Bomb,9,6,9,10
Pecan Dream,6,4,7,9
Pumpkin Spice,8,5,8,10
Blueberry Bliss,7,5,7,9
Lemon Meringue,9,6,9,10
Chocolate Silk,8,5,8,9
Key Lime Tart,6,4,6,9
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/pie_competition.csv
sudo chmod 666 /home/ga/Documents/pie_competition.csv

echo "✅ Created pie competition CSV with biased judge scores"
echo "   - Judge 2 (harsh): scores 4-6"
echo "   - Judge 4 (generous): scores 9-10"
echo "   - Judges 1 & 3 (moderate): scores 6-9"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/pie_competition.csv > /tmp/calc_normalize_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_normalize_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
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

# Position cursor at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Judge Score Normalization Task Setup Complete ==="
echo ""
echo "📊 Task Description:"
echo "   8 pies rated by 4 judges with different scoring styles"
echo "   Judge 2 is harsh (4-6), Judge 4 is generous (9-10)"
echo ""
echo "🎯 Your Goal:"
echo "   1. Recognize the judge bias from the data"
echo "   2. Calculate z-scores to normalize: z = (score - mean) / stdev"
echo "   3. For each pie, average its 4 normalized scores"
echo "   4. Rank pies by average z-scores (not raw scores!)"
echo "   5. Identify top 3 winners fairly"
echo ""
echo "💡 Hint: Simply averaging raw scores is unfair!"
echo "   A pie with [7,5,7,9] might actually be better than [8,6,8,10]"
echo "   when you account for judge bias."