#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Home Brewing Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet as starting point
SHEET_PATH="$WORKSPACE_DIR/brewing_log.xlsx"

cat > /tmp/create_brewing_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Brewing Log"

# We start with a completely blank sheet
# The user needs to create everything from scratch

wb.save(sys.argv[1])
print(f"Blank brewing log spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_brewing_sheet.py
python3 /tmp/create_brewing_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_brewing_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_brewing_task.log || true
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

echo "=== Home Brewing Log Task Setup Complete ==="
echo ""
echo "📝 Task: Create a home brewing log to track 4 batches"
echo ""
echo "Step 1: Create headers (Row 1):"
echo "  - Batch Name, Brew Date, Style, Original Gravity (OG), Final Gravity (FG)"
echo "  - ABV (%), Batch Size (bottles), Total Cost ($), Cost/Bottle ($), Rating (out of 5)"
echo ""
echo "Step 2: Enter 4 batches (Rows 2-5):"
echo "  Batch 1: Summer Haze IPA, 2024-06-15, IPA, 1.065, 1.012, [formula], 48, 52.50, [formula], 5"
echo "  Batch 2: Autumn Amber, 2024-09-22, Amber Ale, 1.055, 1.014, [formula], 48, 38.75, [formula], 3"
echo "  Batch 3: Winter Porter, 2024-12-08, Porter, 1.070, 1.018, [formula], 36, 45.00, [formula], 4"
echo "  Batch 4: Spring Saison, 2025-03-10, Saison, 1.058, 1.008, [formula], 48, 41.25, [formula], 4"
echo ""
echo "Step 3: Create formulas:"
echo "  - ABV (%) = (OG - FG) × 131.25"
echo "  - Cost/Bottle ($) = Total Cost / Batch Size"
echo ""
echo "Step 4: Apply conditional formatting to Rating column (ratings >= 4 highlighted)"
echo ""
echo "Step 5: Add summary section (Rows 7-9):"
echo "  - Average ABV: =AVERAGE(ABV range)"
echo "  - Total Spent: =SUM(Total Cost range)"
echo "  - Successful Batches: =COUNTIF(Rating range, \">=4\")"
echo ""
echo "Step 6: Save (Ctrl+S)"
echo ""
echo "Expected results:"
echo "  - Summer Haze IPA ABV: ~6.96%"
echo "  - Autumn Amber ABV: ~5.38%"
echo "  - Winter Porter ABV: ~6.83%"
echo "  - Spring Saison ABV: ~6.56%"
echo "  - Average ABV: ~6.43%"
echo "  - Total Spent: $177.50"
echo "  - Successful Batches: 3"