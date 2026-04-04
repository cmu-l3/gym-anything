#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Wallpaper Pattern Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create structured CSV template with inputs pre-filled and calculations empty
cat > /home/ga/Documents/wallpaper_calculator_template.csv << 'EOF'
Section,Label,Value
Wall Dimensions,,
,Height (inches),108
,Width (inches),144
,Door Width (inches),36
,,
Wallpaper Specifications,,
,Roll Width (inches),20.5
,Roll Length (inches),396
,Pattern Repeat (inches),21
,,
Calculations,,
,Pattern Repeats Per Roll,
,Usable Length Per Strip (in),
,Strips Per Roll,
,Net Wall Width (in),
,Strips Needed,
,,
Rolls Calculation,,
,Rolls Before Contingency,
,Final Rolls (with 10% contingency),
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/wallpaper_calculator_template.csv
sudo chmod 666 /home/ga/Documents/wallpaper_calculator_template.csv

# Launch LibreOffice Calc with the template
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/wallpaper_calculator_template.csv > /tmp/calc_wallpaper_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_wallpaper_task.log || true
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

# Navigate to first calculation cell (C11 - Pattern Repeats Per Roll)
echo "Positioning cursor at first calculation cell..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to row 11, column C (calculation section)
for i in {1..10}; do
    safe_xdotool ga :1 key Down
    sleep 0.05
done
safe_xdotool ga :1 key Right Right
sleep 0.3

echo "=== Wallpaper Pattern Calculator Task Setup Complete ==="
echo ""
echo "📐 TASK: Build a wallpaper quantity calculator with formulas"
echo ""
echo "📊 PRE-FILLED INPUTS (Do NOT modify):"
echo "  • Wall: 108\" high × 144\" wide"
echo "  • Door: 36\" wide"
echo "  • Roll: 20.5\" wide × 396\" long"
echo "  • Pattern repeat: 21\" vertical"
echo ""
echo "✏️  YOUR TASK: Add formulas in the Calculations section:"
echo "  1. Pattern Repeats Per Roll = FLOOR(roll_length / pattern_repeat)"
echo "  2. Usable Length Per Strip = repeats × pattern_repeat"
echo "  3. Strips Per Roll = FLOOR(usable_length / wall_height)"
echo "  4. Net Wall Width = wall_width - door_width"
echo "  5. Strips Needed = ROUNDUP(net_width / roll_width)"
echo "  6. Rolls Before Contingency = ROUNDUP(strips_needed / strips_per_roll)"
echo "  7. Final Rolls = ROUNDUP(rolls × 1.1) [10% contingency]"
echo ""
echo "🎯 EXPECTED FINAL RESULT: 3 rolls"
echo ""
echo "💡 TIP: Use cell references (e.g., C4, C8) not hardcoded numbers!"