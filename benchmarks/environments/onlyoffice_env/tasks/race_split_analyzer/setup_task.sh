#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Race Split Analyzer Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with race split data
SHEET_PATH="$WORKSPACE_DIR/race_data_raw.xlsx"

cat > /tmp/create_race_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from datetime import time
import sys

wb = Workbook()
wb.remove(wb.active)  # Remove default sheet

# Race 1: Cherry Blossom Half Marathon
# Realistic splits showing runner going out too fast, then slowing significantly
race1_splits = [
    (1, "7:45"),   # Started too fast
    (2, "7:52"),
    (3, "7:58"),
    (4, "8:05"),
    (5, "8:12"),
    (6, "8:18"),
    (7, "8:25"),
    (8, "8:42"),   # Starting to fade
    (9, "9:05"),   # Significantly slower
    (10, "9:45"),  # Hitting the wall
    (11, "10:02"), # Really struggling
    (12, "9:58"),
    (13, "9:35")
]

ws1 = wb.create_sheet("Race 1 - Cherry Blossom")
ws1['A1'] = "Mile"
ws1['B1'] = "Split Time (min:sec)"

# Format headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color="D9E1F2", end_color="D9E1F2", fill_type="solid")
ws1['A1'].font = header_font
ws1['B1'].font = header_font
ws1['A1'].fill = header_fill
ws1['B1'].fill = header_fill

for mile, split in race1_splits:
    ws1[f'A{mile+1}'] = mile
    # Parse MM:SS format and store as time
    minutes, seconds = map(int, split.split(':'))
    ws1[f'B{mile+1}'] = f"{minutes}:{seconds:02d}"
    ws1[f'B{mile+1}'].number_format = 'mm:ss'

# Race 2: Capitol Hill Half Marathon
# Similar pattern but slightly different pacing
race2_splits = [
    (1, "8:02"),
    (2, "8:08"),
    (3, "8:15"),
    (4, "8:22"),
    (5, "8:28"),
    (6, "8:35"),
    (7, "8:48"),
    (8, "9:12"),
    (9, "9:30"),   # Slowing down
    (10, "10:15"), # Hitting wall again
    (11, "10:28"),
    (12, "10:05"),
    (13, "9:42")
]

ws2 = wb.create_sheet("Race 2 - Capitol Hill")
ws2['A1'] = "Mile"
ws2['B1'] = "Split Time (min:sec)"
ws2['A1'].font = header_font
ws2['B1'].font = header_font
ws2['A1'].fill = header_fill
ws2['B1'].fill = header_fill

for mile, split in race2_splits:
    ws2[f'A{mile+1}'] = mile
    minutes, seconds = map(int, split.split(':'))
    ws2[f'B{mile+1}'] = f"{minutes}:{seconds:02d}"
    ws2[f'B{mile+1}'].number_format = 'mm:ss'

# Create empty Analysis sheet
ws3 = wb.create_sheet("Analysis")
ws3['A1'] = "[Create your analysis here]"
ws3['A2'] = "Follow the task instructions to:"
ws3['A3'] = "1. Add proper column headers"
ws3['A4'] = "2. Link race pace data from both race sheets"
ws3['A5'] = "3. Calculate average pace across races"
ws3['A6'] = "4. Flag slow miles (>10% slower than average)"
ws3['A7'] = "5. Add summary statistics below the data"

wb.save(sys.argv[1])
print(f"Race data spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_race_sheet.py
python3 /tmp/create_race_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_race_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_race_task.log || true
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

echo "=== Race Split Analyzer Task Setup Complete ==="
echo "📝 Task Context:"
echo "  You're analyzing pacing consistency across two half-marathon races."
echo "  Both races show significant slowdown in later miles (the dreaded 'wall')."
echo ""
echo "📊 Instructions:"
echo "  1. Go to the 'Analysis' sheet"
echo "  2. Create column headers in Row 1:"
echo "     - A1: 'Mile'"
echo "     - B1: 'Race 1 Pace'"
echo "     - C1: 'Race 2 Pace'"
echo "     - D1: 'Average Pace'"
echo "     - E1: 'Slowdown Flag'"
echo "  3. Format header row: bold + background color + centered"
echo "  4. Fill column A (A2:A14) with mile numbers 1-13"
echo "  5. In column B, link to Race 1 split times (='Race 1 - Cherry Blossom'.B2)"
echo "  6. In column C, link to Race 2 split times (='Race 2 - Capitol Hill'.B2)"
echo "  7. In column D, calculate average pace across both races"
echo "     Hint: Times are tricky! Convert to seconds, average, then back"
echo "     Formula: =(B2+C2)/2 may work if values are time format"
echo "  8. In column E, flag miles where either race was >10% slower than average"
echo "     Formula: =IF(OR((B2-D2)/D2>0.1, (C2-D2)/D2>0.1), \"SLOW\", \"OK\")"
echo "  9. Add summary statistics starting at row 16:"
echo "     - A16: 'Fastest Mile', B16: =MIN(D2:D14)"
echo "     - A17: 'Slowest Mile', B17: =MAX(D2:D14)"
echo "     - A18: 'Pace Variation', B18: =B17-B16"
echo "     - A19: 'Consistency Score', B19: =COUNTIF(E2:E14,\"OK\")/13 (format as %)"
echo "  10. Add borders around summary section (A16:B19)"
echo "  11. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 Expected Results:"
echo "  - Miles 9-12 should be flagged as SLOW (runner hit the wall)"
echo "  - Consistency score should be ~60-70% (8-9 consistent miles out of 13)"