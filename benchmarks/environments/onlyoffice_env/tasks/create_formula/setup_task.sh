#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Formula Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with sample data
SHEET_PATH="$WORKSPACE_DIR/sales_data.xlsx"

cat > /tmp/create_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Sales"

# Add headers
ws['A1'] = "Product"
ws['B1'] = "Q1 Sales"
ws['C1'] = "Q2 Sales"
ws['D1'] = "Q3 Sales"
ws['E1'] = "Q4 Sales"

# Add sample data
products = ["Laptop", "Mouse", "Keyboard", "Monitor", "Headset"]
sales_data = [
    [1200, 1350, 1500, 1400],
    [450, 500, 480, 520],
    [320, 350, 380, 360],
    [890, 920, 950, 910],
    [280, 310, 290, 330]
]

for i, product in enumerate(products, start=2):
    ws[f'A{i}'] = product
    for j, sales in enumerate(sales_data[i-2], start=2):
        ws.cell(row=i, column=j, value=sales)

# Add formula instructions
ws['A8'] = "Total Sales:"
ws['A9'] = "Average Sales:"
ws['A10'] = "Max Quarter:"

# The user needs to add formulas in column B
ws['B8'] = "[Add SUM formula for all Q1-Q4 sales here]"
ws['B9'] = "[Add AVERAGE formula for all Q1-Q4 sales here]"
ws['B10'] = "[Add MAX formula for all Q1-Q4 sales here]"

wb.save(sys.argv[1])
print(f"Spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_sheet.py
python3 /tmp/create_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_sheet_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_sheet_task.log || true
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

echo "=== Create Formula Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. In cell B8, create formula: =SUM(B2:E6)"
echo "  2. In cell B9, create formula: =AVERAGE(B2:E6)"
echo "  3. In cell B10, create formula: =MAX(B2:E6)"
echo "  4. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected results:"
echo "  - Total Sales: 11720"
echo "  - Average Sales: 586"
echo "  - Max Quarter: 1500"
