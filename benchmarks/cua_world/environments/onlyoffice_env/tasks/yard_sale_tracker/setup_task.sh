#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Yard Sale Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial blank spreadsheet
SHEET_PATH="$WORKSPACE_DIR/yard_sale_tracker.xlsx"

cat > /tmp/create_yard_sale_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Yard Sale"

# Add instruction in cell A1 (will be replaced by agent)
ws['A1'] = "CREATE YARD SALE TRACKER HERE"
ws['A1'].font = Font(bold=True, size=12)

# Add helpful reminder in A3
ws['A3'] = "TASK: Create headers (Item, Owner, Price, Status, Notes) in row 1"
ws['A4'] = "Add at least 12 items from 4 owners (You, Johnsons, Patels, Maria)"
ws['A5'] = "Create summary section with formulas for each owner's total earnings"
ws['A6'] = "Format prices as currency and headers as bold with color"

# Set some column widths for better visibility
ws.column_dimensions['A'].width = 30
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 25

wb.save(sys.argv[1])
print(f"Yard sale tracker spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_yard_sale_sheet.py
python3 /tmp/create_yard_sale_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_yard_sale_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_yard_sale_task.log || true
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

echo "=== Yard Sale Tracker Task Setup Complete ==="
echo "📝 Scenario: You and three neighbors are organizing a joint yard sale"
echo ""
echo "Instructions:"
echo "  1. Create headers in row 1: Item, Owner, Price, Status, Notes"
echo "  2. Add at least 12 items (yard sale inventory) with:"
echo "     - Mix of items from You, Johnsons, Patels, and Maria"
echo "     - Realistic prices ($1-$75)"
echo "     - Variety: furniture, electronics, books, kitchen, toys, tools, etc."
echo "  3. Create summary section (around row 17+):"
echo "     - 'PROCEEDS SUMMARY' header (merged, bold, centered)"
echo "     - List each owner with FORMULAS calculating their total earnings"
echo "     - Grand total with formula summing all items"
echo "  4. Format:"
echo "     - Header row: bold, background color, centered"
echo "     - Price column: currency format ($)"
echo "     - Adjust column widths for readability"
echo "  5. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Example items: Coffee maker ($8), Kids bike ($25), Garden tools ($15), Books ($20)..."