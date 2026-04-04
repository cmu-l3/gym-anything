#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Wedding Gig Setlist Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with template data
SHEET_PATH="$WORKSPACE_DIR/wedding_setlist_readiness.xlsx"

cat > /tmp/create_setlist_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Setlist Tracker"

# Add headers (Row 1)
headers = [
    "Song Title",
    "Guitar (%)",
    "Bass (%)",
    "Drums (%)",
    "Vocals (%)",
    "Band Avg (%)",
    "Target (%)",
    "Gap to Target",
    "Priority"
]

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='center')

# Wedding song data with current band readiness
songs_data = [
    ["At Last (Etta James)", 90, 85, 95, 100],
    ["Thinking Out Loud (Ed Sheeran)", 100, 100, 90, 95],
    ["Can't Help Falling in Love", 95, 90, 100, 100],
    ["Marry You (Bruno Mars)", 80, 75, 85, 90],
    ["September (Earth Wind & Fire)", 30, 40, 60, 50],
    ["Uptown Funk", 25, 30, 70, 40],
    ["Sweet Caroline", 60, 65, 80, 75],
    ["I Wanna Dance with Somebody", 20, 25, 50, 35]
]

# Add song data (Rows 2-9)
for row_idx, song_data in enumerate(songs_data, start=2):
    for col_idx, value in enumerate(song_data, start=1):
        ws.cell(row=row_idx, column=col_idx, value=value)

# Add Target values (100% for all songs in column G)
for row_idx in range(2, 10):
    ws.cell(row=row_idx, column=7, value=100)

# Add placeholder instructions for formulas
for row_idx in range(2, 10):
    ws.cell(row=row_idx, column=6, value="[Add AVERAGE formula]")
    ws.cell(row=row_idx, column=8, value="[Add Gap formula]")
    ws.cell(row=row_idx, column=9, value="[Add Priority]")

# Adjust column widths for readability
ws.column_dimensions['A'].width = 30
ws.column_dimensions['B'].width = 12
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 14
ws.column_dimensions['G'].width = 12
ws.column_dimensions['H'].width = 14
ws.column_dimensions['I'].width = 16

wb.save(sys.argv[1])
print(f"Wedding setlist spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_setlist_sheet.py
python3 /tmp/create_setlist_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Wedding setlist spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_setlist_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_setlist_task.log || true
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

echo "=== Wedding Gig Setlist Task Setup Complete ==="
echo "📝 Context: Your band 'The Rusty Strings' has a wedding gig in 3 weeks ($800 payout!)"
echo "   The couple requested 8 specific songs, but your band only knows some of them well."
echo ""
echo "📋 Your task:"
echo "  1. In column F (Band Avg %), create AVERAGE formulas for rows 2-9"
echo "     Example for row 2: =AVERAGE(B2:E2)"
echo "  2. In column H (Gap to Target), create subtraction formulas"
echo "     Example for row 2: =G2-F2"
echo "  3. In column I (Priority), add priority labels based on Band Avg:"
echo "     - Band Avg < 50%: 'HIGH PRIORITY'"
echo "     - Band Avg 50-79%: 'MEDIUM PRIORITY'"
echo "     - Band Avg >= 80%: 'LOW PRIORITY'"
echo "  4. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 Tip: You can use IF formulas for priorities or enter them manually"
echo "   Example IF formula: =IF(F2<50,\"HIGH PRIORITY\",IF(F2<80,\"MEDIUM PRIORITY\",\"LOW PRIORITY\"))"