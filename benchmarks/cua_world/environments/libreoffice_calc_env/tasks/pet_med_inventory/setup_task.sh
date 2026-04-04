#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Pet Medication Inventory Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy pet medication CSV data with intentional quality issues
cat > /home/ga/Documents/pet_medications_raw.csv << 'CSVEOF'
Pet Name,Medication,Start Date,Last Refill,Pills per Bottle,Daily Dosage,Cost per Bottle
Luna,Thyroid Pills,01/15/2024,03-Apr-24,60,2,28.50
Max,Arthritis Med,2023-11-20,04/01/2024,90,1.5,45.00
Bella,Allergy Pills,02/28/2024,,30,1,22.00
Luna,Heart Med,01/15/24,03/15/2024,60,1,67.00
Max,Probiotic,11-20-2023,2024-04-10,120,2,35.50
Bella,Flea Prevention,28/02/2024,04-05-24,6,0.033,89.99
CSVEOF

sudo chown ga:ga /home/ga/Documents/pet_medications_raw.csv
sudo chmod 666 /home/ga/Documents/pet_medications_raw.csv

echo "✅ Created pet_medications_raw.csv with messy data"
ls -lh /home/ga/Documents/pet_medications_raw.csv

# Convert CSV to ODS using LibreOffice headless mode
echo "Converting CSV to ODS format..."
sudo -u ga bash -c "DISPLAY=:1 libreoffice --headless --convert-to ods --outdir /home/ga/Documents /home/ga/Documents/pet_medications_raw.csv > /tmp/convert_pet_meds.log 2>&1" || {
    echo "⚠️ Headless conversion failed, will open in Calc directly"
    cat /tmp/convert_pet_meds.log || true
}

# Check if conversion succeeded
if [ -f "/home/ga/Documents/pet_medications_raw.ods" ]; then
    # Rename to working file
    sudo -u ga mv /home/ga/Documents/pet_medications_raw.ods /home/ga/Documents/pet_medications.ods
    sudo chown ga:ga /home/ga/Documents/pet_medications.ods
    sudo chmod 666 /home/ga/Documents/pet_medications.ods
    echo "✅ Converted to pet_medications.ods"
    FILE_TO_OPEN="/home/ga/Documents/pet_medications.ods"
else
    # Fallback: rename CSV to working file (Calc can open CSV directly)
    sudo -u ga cp /home/ga/Documents/pet_medications_raw.csv /home/ga/Documents/pet_medications.csv
    sudo chown ga:ga /home/ga/Documents/pet_medications.csv
    sudo chmod 666 /home/ga/Documents/pet_medications.csv
    echo "⚠️ Using CSV format as fallback"
    FILE_TO_OPEN="/home/ga/Documents/pet_medications.csv"
fi

# Launch LibreOffice Calc with the file
echo "Launching LibreOffice Calc with pet medication data..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore $FILE_TO_OPEN > /tmp/calc_pet_med_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 20; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_pet_med_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
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
        # Maximize window for better visibility
        safe_xdotool ga :1 key F11 || true
        sleep 0.5
    fi
fi

# Move cursor to cell A1 (start position)
safe_xdotool ga :1 key ctrl+Home || true
sleep 0.3

echo ""
echo "=== Pet Medication Inventory Task Setup Complete ==="
echo ""
echo "📋 Task Overview:"
echo "  • File opened: $FILE_TO_OPEN"
echo "  • 6 medication records for 3 pets (Luna, Max, Bella)"
echo "  • Data has intentional quality issues (mixed date formats, missing values)"
echo ""
echo "📝 Your Task:"
echo "  1. Clean data: Standardize date formats in 'Last Refill' column"
echo "  2. Add column I 'Days Since Refill': =TODAY() - [Last Refill]"
echo "  3. Add column J 'Pills Used': =[Daily Dosage] * [Days Since Refill]"
echo "  4. Add column K 'Pills Remaining': =[Pills per Bottle] - [Pills Used]"
echo "  5. Add column L 'Reorder Needed?': =IF([Pills Remaining] < [Daily Dosage]*7, \"YES\", \"NO\")"
echo "  6. Add column M 'Days Until Empty': =[Pills Remaining] / [Daily Dosage]"
echo "  7. Add column N 'Reorder Cost': =IF([Reorder Needed?]=\"YES\", [Cost per Bottle], 0)"
echo "  8. Add SUM formula at bottom of Reorder Cost column"
echo ""
echo "💡 Tip: Start by standardizing dates, then build formulas step-by-step"
echo ""