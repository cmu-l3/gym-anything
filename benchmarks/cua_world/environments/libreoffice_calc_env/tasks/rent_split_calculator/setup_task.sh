#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Fair Rent Split Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with room characteristics data
cat > /home/ga/Documents/rent_split_data.csv << 'EOF'
Tenant Name,Room,Sq Ft,Private Bath,Parking,Floor,Light (1-5),Weighted Score,Rent Proportion,Monthly Rent
Alex,A,180,Yes,Yes,3,4,,,
Blake,B,140,No,No,2,3,,,
Casey,C,160,Yes,No,3,5,,,
Drew,D,200,Yes,Yes,1,2,,,
,,,,,TOTAL:,,,,3200
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/rent_split_data.csv
sudo chmod 666 /home/ga/Documents/rent_split_data.csv

echo "✅ Created rent_split_data.csv with room characteristics"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/rent_split_data.csv > /tmp/calc_rent_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_rent_task.log || true
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

# Position cursor at first empty formula cell (H2 - Weighted Score for first room)
echo "Positioning cursor at H2 (first weighted score cell)..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to H2
safe_xdotool ga :1 key Right Right Right Right Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Fair Rent Split Calculator Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. Calculate Weighted Scores (Column H) using the formula:"
echo "     =C2*2.5 + IF(D2=\"Yes\",150,0) + IF(E2=\"Yes\",100,0) + F2*20 + G2*30"
echo "  2. Calculate total of weighted scores (sum of H2:H5)"
echo "  3. Calculate Rent Proportions (Column I): each score / total score"
echo "  4. Calculate Monthly Rent (Column J): proportion * 3200"
echo "  5. Verify that monthly rents sum to $3,200"
echo ""
echo "💡 Tip: Use absolute references ($) for total score when calculating proportions"
echo "💡 Tip: Better rooms should have higher weighted scores and rent"