#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fermentation Batch Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Calculate dates for batches (days ago from today)
BATCH_K01_DAYS_AGO=15
BATCH_M03_DAYS_AGO=45
BATCH_K02_DAYS_AGO=8
BATCH_M04_DAYS_AGO=68

# Calculate actual dates
BATCH_K01_DATE=$(date -d "$BATCH_K01_DAYS_AGO days ago" +%Y-%m-%d)
BATCH_M03_DATE=$(date -d "$BATCH_M03_DAYS_AGO days ago" +%Y-%m-%d)
BATCH_K02_DATE=$(date -d "$BATCH_K02_DAYS_AGO days ago" +%Y-%m-%d)
BATCH_M04_DATE=$(date -d "$BATCH_M04_DAYS_AGO days ago" +%Y-%m-%d)

# Create batch notes file on Desktop for reference
NOTES_PATH="/home/ga/Desktop/batch_notes.txt"
cat > "$NOTES_PATH" << EOF
FERMENTATION BATCH TRACKING - CURRENT BATCHES
==============================================

You have 4 batches currently fermenting that need tracking:

Batch-K-01 (Kombucha):
  - Started: $BATCH_K01_DATE ($BATCH_K01_DAYS_AGO days ago)
  - Target fermentation: 12 days
  - Should be ready by now!

Batch-M-03 (Mead):
  - Started: $BATCH_M03_DATE ($BATCH_M03_DAYS_AGO days ago)
  - Target fermentation: 60 days
  - Still fermenting...

Batch-K-02 (Kombucha):
  - Started: $BATCH_K02_DATE ($BATCH_K02_DAYS_AGO days ago)
  - Target fermentation: 12 days
  - Not ready yet

Batch-M-04 (Mead):
  - Started: $BATCH_M04_DATE ($BATCH_M04_DAYS_AGO days ago)
  - Target fermentation: 60 days
  - Should be ready to bottle!

==============================================
TASK: Create a tracking spreadsheet with:
  - Column A: Batch Name
  - Column B: Beverage Type
  - Column C: Start Date
  - Column D: Target Days
  - Column E: Days Elapsed (formula using TODAY())
  - Column F: Status (IF formula: "Ready to Bottle" if elapsed >= target, else "Still Fermenting")

Save as: fermentation_tracker.xlsx in Documents/Spreadsheets/
EOF

chown ga:ga "$NOTES_PATH"
echo "✅ Batch notes created at: $NOTES_PATH"

# Create a blank spreadsheet to start with
SHEET_PATH="$WORKSPACE_DIR/fermentation_tracker.xlsx"

cat > /tmp/create_tracker_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

# Create a completely blank workbook
wb = Workbook()
ws = wb.active
ws.title = "Fermentation Tracker"

# Save blank workbook
wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_tracker_sheet.py
python3 /tmp/create_tracker_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_fermentation_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_fermentation_task.log || true
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

echo "=== Fermentation Batch Tracker Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "Check the batch_notes.txt file on Desktop for batch information."
echo ""
echo "Create a tracking spreadsheet with these columns in row 1:"
echo "  A1: Batch Name"
echo "  B1: Beverage Type"
echo "  C1: Start Date"
echo "  D1: Target Days"
echo "  E1: Days Elapsed"
echo "  F1: Status"
echo ""
echo "Enter the 4 batches (rows 2-5) with their data from batch_notes.txt"
echo ""
echo "Create formulas:"
echo "  Column E: =TODAY()-C2 (calculate days elapsed)"
echo "  Column F: =IF(E2>=D2,\"Ready to Bottle\",\"Still Fermenting\")"
echo ""
echo "Copy formulas down to all batch rows, then save (Ctrl+S)"
echo ""
echo "Expected results:"
echo "  - Batch-K-01: Ready to Bottle (15 days, target 12)"
echo "  - Batch-M-03: Still Fermenting (45 days, target 60)"
echo "  - Batch-K-02: Still Fermenting (8 days, target 12)"
echo "  - Batch-M-04: Ready to Bottle (68 days, target 60)"