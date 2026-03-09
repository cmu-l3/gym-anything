#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Backyard Flock Production Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet as starting point
SHEET_PATH="$WORKSPACE_DIR/egg_production_log.xlsx"

cat > /tmp/create_egg_tracker.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

# Create a new blank workbook
wb = Workbook()
ws = wb.active
ws.title = "Egg Production"

# Just create a completely blank spreadsheet
# The user will build the entire structure

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_egg_tracker.py
python3 /tmp/create_egg_tracker.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_egg_tracker.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_egg_tracker.log || true
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

echo "=== Backyard Flock Production Tracker Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Create a weekly egg production tracker with the following structure:"
echo ""
echo "Row 1: Title 'Backyard Flock Egg Production Log'"
echo "Row 2: Subtitle 'Week of January 6-12, 2025'"
echo "Row 4: Headers - A4: 'Date' | B4: 'Henrietta' | C4: 'Nugget' | D4: 'Pepper' | E4: 'Goldie' | F4: 'Daily Total'"
echo ""
echo "Rows 5-11: Enter dates and egg counts (0 or 1 per hen per day):"
echo "  A5-A11: Mon 1/6, Tue 1/7, Wed 1/8, Thu 1/9, Fri 1/10, Sat 1/11, Sun 1/12"
echo "  Henrietta (B5-B11): 1, 0, 1, 1, 0, 1, 1"
echo "  Nugget (C5-C11):    0, 1, 0, 1, 1, 0, 1"
echo "  Pepper (D5-D11):    0, 0, 0, 1, 0, 0, 0"
echo "  Goldie (E5-E11):    1, 1, 0, 1, 1, 1, 1"
echo ""
echo "Row 12: Weekly totals with SUM formulas:"
echo "  A12: 'Weekly Total' | B12: =SUM(B5:B11) | C12: =SUM(C5:C11) | etc."
echo ""
echo "Row 13: Daily averages with AVERAGE formulas:"
echo "  A13: 'Avg per Day' | B13: =AVERAGE(B5:B11) | C13: =AVERAGE(C5:C11) | etc."
echo ""
echo "Column F (rows 5-11): Daily totals with SUM formulas:"
echo "  F5: =SUM(B5:E5) | F6: =SUM(B6:E6) | etc."
echo ""
echo "Conditional Formatting: Highlight cells B12:E12 RED if value < 3"
echo ""
echo "Save the file (Ctrl+S) when complete."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"