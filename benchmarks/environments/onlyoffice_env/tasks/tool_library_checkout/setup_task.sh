#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Tool Library Checkout Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet for the task
SHEET_PATH="$WORKSPACE_DIR/tool_checkout.xlsx"

cat > /tmp/create_tool_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Tool Checkout"

# Just create a blank spreadsheet - the agent needs to create everything
# We'll add a small instruction note in cell A1
ws['A1'] = "Create Tool Library Checkout Tracker Here"
ws['A1'].font = Font(italic=True, color="808080")

# Set column widths for better visibility
ws.column_dimensions['A'].width = 20
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 12

wb.save(sys.argv[1])
print(f"Spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_tool_sheet.py
python3 /tmp/create_tool_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_tool_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_tool_task.log || true
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

echo "=== Tool Library Checkout Task Setup Complete ==="
echo ""
echo "📝 SCENARIO:"
echo "You volunteer at a community tool library. Members are upset about lost tools"
echo "and overdue items. You need a tracking spreadsheet ready for tomorrow's meeting."
echo "The board wants to charge \$2/day late fees after the 7-day loan period."
echo ""
echo "🎯 YOUR TASK:"
echo "  1. Create header row (row 1) with columns:"
echo "     - Tool Name"
echo "     - Borrower Name"
echo "     - Checkout Date"
echo "     - Due Date"
echo "     - Days Out"
echo "     - Status"
echo "     - Late Fee"
echo ""
echo "  2. Add 5 checkout records with realistic data"
echo "     - Include at least 2 OVERDUE items (>7 days out)"
echo "     - Include at least 2 OK items (≤7 days out)"
echo ""
echo "  3. Create formulas:"
echo "     - Days Out: Calculate days from checkout to today (use TODAY())"
echo "     - Status: Show 'OVERDUE' if days out > 7, else 'OK'"
echo "     - Late Fee: Calculate \$2/day beyond 7 days (\$0 if not overdue)"
echo ""
echo "  4. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 HINTS:"
echo "  - Use =TODAY() to get current date"
echo "  - Days Out formula: =TODAY()-C2 (where C2 is checkout date)"
echo "  - Status formula: =IF(E2>7,\"OVERDUE\",\"OK\")"
echo "  - Late Fee formula: =MAX(0,(E2-7)*2)"
echo "  - For overdue items: use dates 10-20 days ago"
echo "  - For OK items: use dates 3-6 days ago"
echo ""