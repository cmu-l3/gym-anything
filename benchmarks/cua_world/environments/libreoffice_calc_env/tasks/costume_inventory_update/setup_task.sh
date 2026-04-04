#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Theater Costume Inventory Update Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create costume inventory CSV
cat > /home/ga/Documents/costume_inventory.csv << 'EOF'
Item ID,Item Name,Type,Size,Character,Status,Condition,Notes
C001,Renaissance Gown,Costume,M,Lady Capulet,Available,Good,
C002,Pirate Coat,Costume,L,Captain Hook,Available,Good,
C003,Flapper Dress,Costume,S,Daisy Buchanan,Available,Good,
C004,Tuxedo,Costume,L,James Bond,Available,Good,
C005,Victorian Jacket,Costume,M,Sherlock Holmes,Checked Out,Good,
C006,Ballet Tutu,Costume,S,Sugarplum Fairy,Available,Good,
C007,Cowboy Hat,Accessory,One Size,Woody,Available,Good,
C008,Medieval Tunic,Costume,L,King Arthur,Checked Out,Good,
C009,Witch Hat,Accessory,One Size,Elphaba,Available,Good,
C010,Evening Gloves,Accessory,M,Holly Golightly,Available,Good,
C011,Top Hat,Accessory,One Size,Phantom,Checked Out,Good,
C012,Police Uniform,Costume,L,Officer Krupke,Available,Good,
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/costume_inventory.csv
sudo chmod 666 /home/ga/Documents/costume_inventory.csv

echo "✅ Created costume inventory CSV with 12 items"
echo "   - 3 items marked as 'Checked Out' (need status update)"
echo "   - 2 items will need damage marking and notes"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/costume_inventory.csv > /tmp/calc_costume_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_costume_task.log || true
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

# Ensure cursor is at beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Theater Costume Inventory Update Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "   It's Sunday evening after the production finale. Several costumes"
echo "   were returned but not logged. Dress rehearsal is Tuesday morning."
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "   1. Update Status to 'Available' for returned items:"
echo "      - Row 6: Victorian Jacket (currently Checked Out)"
echo "      - Row 9: Medieval Tunic (currently Checked Out)"
echo "      - Row 12: Top Hat (currently Checked Out)"
echo ""
echo "   2. Mark damaged items (change Condition to 'Damaged'):"
echo "      - Row 6: Victorian Jacket"
echo "      - Row 9: Medieval Tunic"
echo ""
echo "   3. Add damage notes in Notes column (Column H):"
echo "      - Row 6: 'Torn sleeve, needs stitching' (or similar)"
echo "      - Row 9: 'Wine stain on front, requires cleaning' (or similar)"
echo ""
echo "   4. Apply conditional formatting to Condition column (Column G):"
echo "      - Select range G2:G13"
echo "      - Format → Conditional Formatting → Condition..."
echo "      - Rule: Cell value is equal to 'Damaged'"
echo "      - Set background color to red or orange"
echo ""
echo "💡 TIPS:"
echo "   - Use arrow keys to navigate to specific cells"
echo "   - Press F2 or double-click to edit cell contents"
echo "   - Ctrl+S to save when done"
echo ""