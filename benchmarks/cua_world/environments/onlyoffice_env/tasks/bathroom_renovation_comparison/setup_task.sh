#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bathroom Renovation Comparison Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet for the task
SHEET_PATH="$WORKSPACE_DIR/bathroom_renovation_comparison.xlsx"

cat > /tmp/create_renovation_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Renovation Comparison"

# Create a completely blank spreadsheet
# The agent will fill in all headers, data, and formulas

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_renovation_sheet.py
python3 /tmp/create_renovation_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_renovation_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_renovation_task.log || true
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

echo "=== Bathroom Renovation Comparison Task Setup Complete ==="
echo "📝 Scenario: You're renovating your bathroom and have collected price quotes"
echo "           from 3 hardware stores. Create a comparison spreadsheet to decide"
echo "           where to buy materials."
echo ""
echo "Instructions:"
echo "  1. Create headers in row 1:"
echo "     A1: 'Material' | B1: 'Home Depot' | C1: 'Lowe's' | D1: 'Builder's Best'"
echo ""
echo "  2. Enter materials in column A (rows 2-6):"
echo "     A2: Toilet | A3: Vanity Sink | A4: Faucet | A5: Tile (per box) | A6: Grout"
echo ""
echo "  3. Enter Home Depot prices (column B):"
echo "     B2: 189.99 | B3: 245.00 | B4: 78.50 | B5: 35.99 | B6: 22.49"
echo ""
echo "  4. Enter Lowe's prices (column C):"
echo "     C2: 199.99 | C3: 229.99 | C4: 72.99 | C5: 38.50 | C6: 19.99"
echo ""
echo "  5. Enter Builder's Best prices (column D):"
echo "     D2: 179.99 | D3: 259.00 | D4: 75.00 | D5: 33.99 | D6: 21.50"
echo ""
echo "  6. Add total label in A7: 'TOTAL'"
echo ""
echo "  7. Create SUM formulas for store totals:"
echo "     B7: =SUM(B2:B6) | C7: =SUM(C2:C6) | D7: =SUM(D2:D6)"
echo ""
echo "  8. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected totals:"
echo "  - Home Depot: \$571.97"
echo "  - Lowe's: \$561.46 (cheapest!)"
echo "  - Builder's Best: \$569.48"