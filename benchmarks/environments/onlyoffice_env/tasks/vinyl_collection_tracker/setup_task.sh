#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Vinyl Collection Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
SPREADSHEET_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$SPREADSHEET_DIR"

# Create the unstructured notes file with 10 vinyl records
NOTES_FILE="$DOCS_DIR/record_notes.txt"

cat > "$NOTES_FILE" << 'EOF'
MARCUS'S VINYL PURCHASE NOTES - JAZZ COLLECTION
================================================

Record #1:
Miles Davis - Kind of Blue (Blue Note pressing)
Bought 3/15/2024 from Dave's Records for $45
Condition: VG+ (some light surface marks)
Similar ones selling for $65-75 online now

---

Record #2:
John Coltrane - A Love Supreme (Impulse! original)
Estate sale in Richmond, 1/22/2024, paid $30
Near Mint condition! Steal of a century
Current value probably $120-140

---

Record #3:
Thelonious Monk - Brilliant Corners
Discogs purchase 4/2/2024 - $55 shipped
Excellent condition, just minor sleeve wear
Market value around $60

---

Record #4:
Bill Evans - Waltz for Debby (Riverside original)
Record store find on 2/10/2024, $25
VG condition (some clicks and pops)
Worth about $40 now

---

Record #5:
Charles Mingus - Ah Um (Columbia 6-eye)
eBay purchase 12/30/2023, paid $80 (ouch!)
VG+ condition
Current comps showing $70-75 (overpaid!)

---

Record #6:
Herbie Hancock - Head Hunters
Local shop 3/28/2024, $20
G+ condition (very worn but playable)
Market is around $25 for this condition

---

Record #7:
Dave Brubeck - Time Out
Garage sale score! 1/15/2024, $5
Excellent condition, couldn't believe it
Worth $50 easy

---

Record #8:
Sonny Rollins - Saxophone Colossus (Prestige)
Record fair 4/10/2024, paid $65
Near Mint, original pressing
Current value $90-100

---

Record #9:
Cannonball Adderley - Somethin' Else (Blue Note)
Online purchase 2/25/2024, $70
VG+ condition, clean copy
Market value around $85

---

Record #10:
Art Blakey - Moanin' (Blue Note original)
Estate sale treasure 1/8/2024, paid $40
Excellent condition, barely played
Worth $110-120 now!

---

END OF NOTES

TASK: Create a spreadsheet to track these records with:
- Purchase and current value data
- Formulas to calculate profit/loss and ROI %
- Summary statistics (total invested, current value, avg ROI)
- Professional formatting
EOF

chown ga:ga "$NOTES_FILE"

echo "✅ Record notes created at: $NOTES_FILE"

# Create initial blank spreadsheet
SHEET_PATH="$SPREADSHEET_DIR/vinyl_collection.xlsx"

cat > /tmp/create_vinyl_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Sheet1"

# Add a helpful note in the first cell
ws['A1'] = "Create vinyl collection tracker here"
ws['A2'] = "See /home/ga/Documents/record_notes.txt for data"

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_vinyl_sheet.py
python3 /tmp/create_vinyl_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Initial spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_vinyl_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_vinyl_task.log || true
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

echo "=== Vinyl Collection Tracker Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Read the unstructured notes from: /home/ga/Documents/record_notes.txt"
echo "  2. Create a structured spreadsheet with these columns:"
echo "     - Album Title"
echo "     - Artist"
echo "     - Purchase Date (MM/DD/YYYY format)"
echo "     - Purchase Source"
echo "     - Purchase Price (numeric, use currency formatting)"
echo "     - Condition"
echo "     - Estimated Current Value (numeric, use currency formatting)"
echo "     - Profit/Loss (formula: Current Value - Purchase Price)"
echo "     - ROI % (formula: (Current Value - Purchase Price) / Purchase Price * 100)"
echo "  3. Enter all 10 records from the notes"
echo "  4. Create formulas for Profit/Loss and ROI % columns"
echo "  5. Add a summary section below the data with:"
echo "     - Total Invested: =SUM(purchase prices)"
echo "     - Current Collection Value: =SUM(current values)"
echo "     - Overall Profit/Loss: =SUM(profit/loss column)"
echo "     - Average ROI: =AVERAGE(ROI column)"
echo "  6. Apply formatting:"
echo "     - Make header row bold"
echo "     - Apply currency formatting to price columns"
echo "     - Apply percentage formatting to ROI column"
echo "     - Add background color to header row"
echo "  7. Sort data by Purchase Date OR by ROI %"
echo "  8. Save as: /home/ga/Documents/Spreadsheets/vinyl_collection.xlsx"
echo ""
echo "Expected calculations:"
echo "  - Total Invested: ~$435"
echo "  - Current Value: ~$720"
echo "  - Overall Profit: ~$285"
echo "  - Average ROI: ~70%"