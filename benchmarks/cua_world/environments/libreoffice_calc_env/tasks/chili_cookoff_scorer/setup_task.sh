#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Chili Cook-Off Score Normalizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV file with raw judge scores (different scales, missing data)
cat > /home/ga/Documents/chili_scores_raw.csv << 'EOF'
Contestant,Judge1(1-10),Judge2(1-10),Judge3(1-5),Judge4(1-5)
Spicy Red,8,9,4,5
Smoky Blues,7,8,3,4
Three Bean,9,,5,5
Texas Heat,6,7,4,3
Cincinnati Style,10,9,5,5
White Chili,5,6,2,3
Green Chile,8,7,4,4
Sweet & Savory,7,8,3,
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/chili_scores_raw.csv
sudo chmod 666 /home/ga/Documents/chili_scores_raw.csv

echo "✅ Created chili_scores_raw.csv with judge scores"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/chili_scores_raw.csv > /tmp/calc_chili_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_chili_task.log || true
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Chili Cook-Off Score Normalizer Task Setup Complete ==="
echo "📝 Task: Normalize judge scores and determine competition winners"
echo ""
echo "📋 Instructions:"
echo "  1. Judges 1-2 used 1-10 scale (keep as-is)"
echo "  2. Judges 3-4 used 1-5 scale (convert to 1-10 by multiplying by 2)"
echo "  3. Some judges didn't score all entries (handle missing data)"
echo "  4. Calculate average score per contestant (exclude missing scores)"
echo "  5. Rank contestants (1=highest score)"
echo "  6. Award prizes: 1st=$250, 2nd=$150, 3rd=$100"
echo ""
echo "💡 Hints:"
echo "  - Use IF(ISBLANK(...), ...) to handle missing data"
echo "  - AVERAGE function automatically ignores blanks"
echo "  - Use RANK function for rankings"
echo "  - Total prize pool is $500"