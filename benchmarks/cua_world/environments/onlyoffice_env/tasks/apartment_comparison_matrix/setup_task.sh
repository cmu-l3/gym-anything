#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Apartment Comparison Matrix Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the apartment notes text file with rough data
NOTES_PATH="$WORKSPACE_DIR/apartment_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
APARTMENT SEARCH NOTES - Need to decide by Friday!
=====================================================

Apt 1 - Maple St: $1450/mo, 2BR, quiet area, includes heat, parking $75/mo, 15min to work, nice landlord but old kitchen

Apt 2 - Oak Ave: $1600, 2BR, downtown, util ~$120/mo, street parking only, 8min walk to work, new reno, noisy street

Apt 3 - Pine Road: $1350, 1BR+den, residential, utilities avg $85, parking free, 22min to work, has washer/dryer in unit!, smaller

Apt 4 - Birch Blvd: $1550, 2BR, near park, heat incl but electric ~$60, parking $50, 12min to work, ground floor (safety concern?), pet-friendly

Apt 5 - Cedar Lane: $1700, 2BR, modern building, all util incl, parking incl, 18min to work, gym in building, but corporate landlord (bad reviews)

NEED TO ORGANIZE THIS INTO A SPREADSHEET TO COMPARE!!!
EOF

chown ga:ga "$NOTES_PATH"
echo "✅ Apartment notes created at: $NOTES_PATH"

# Create a blank spreadsheet file
SHEET_PATH="$WORKSPACE_DIR/apartment_comparison.xlsx"

cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Apartment Comparison"

# Just create a blank sheet with a hint
ws['A1'] = "Create your apartment comparison here!"
ws['A2'] = "Refer to apartment_notes.txt for the data"

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_apartment_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_apartment_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Apartment Comparison Matrix Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "You've been apartment hunting for a week and have visited 5 apartments."
echo "Landlords are pressuring you for quick decisions!"
echo ""
echo "📝 YOUR TASK:"
echo "  1. Read the rough notes in: $NOTES_PATH"
echo "  2. Create a comparison spreadsheet with:"
echo "     - Header row: Apartment, Base Rent, Utilities, Parking, Total Cost, Commute, Key Feature"
echo "     - 5 apartment rows with all data"
echo "     - FORMULAS in Total Cost column (=rent+utilities+parking)"
echo "     - Bold formatting for headers"
echo "  3. Save the file (Ctrl+S)"
echo ""
echo "💡 TIP: Use formulas so you can easily update numbers if landlords change prices!"
echo ""
echo "Expected result: A clear decision matrix to help you choose the best apartment"