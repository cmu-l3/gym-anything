#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Craft Fair Pricing Sheet Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet template
SHEET_PATH="$WORKSPACE_DIR/craft_fair_pricing.xlsx"

cat > /tmp/create_pricing_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Pricing Sheet"

# Column widths for better readability
ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 13
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 13
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 11
ws.column_dimensions['G'].width = 13
ws.column_dimensions['H'].width = 15
ws.column_dimensions['I'].width = 16

# Create header row with bold formatting
headers = [
    'Product Name', 'Material Cost', 'Time (hours)', 'Hourly Rate',
    'Total Cost', 'Markup %', 'Selling Price', 'Quantity to Bring', 'Potential Revenue'
]

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")
    cell.alignment = Alignment(horizontal='center', vertical='center')

# Pre-fill product names and hourly rate (constant for all products)
products = [
    'Wire-wrapped earrings',
    'Art prints (8x10)',
    'Ceramic mugs',
    'Handmade notebooks',
    'Resin coasters (set of 4)'
]

for row_idx, product in enumerate(products, start=2):
    ws.cell(row=row_idx, column=1, value=product)  # Product name
    ws.cell(row=row_idx, column=4, value=20)       # Hourly rate ($20 for all)

# Add instruction cells below the data
ws.cell(row=8, column=1, value='--- SUMMARY SECTION ---')
ws.cell(row=8, column=1).font = Font(bold=True)

ws.cell(row=9, column=1, value='Total Inventory Value')
ws.cell(row=10, column=1, value='Projected Revenue (100% sellthrough)')
ws.cell(row=11, column=1, value='Projected Revenue (60% sellthrough)')
ws.cell(row=12, column=1, value='Profit Margin (60% scenario)')

# Add detailed instructions
ws.cell(row=14, column=1, value='═══ INSTRUCTIONS ═══')
ws.cell(row=14, column=1).font = Font(bold=True, size=12)

instructions = [
    '',
    '📝 STEP 1: Fill in the following data for each product (rows 2-6):',
    '   • Material Cost (column B): $4.50, $2.00, $8.00, $5.50, $6.00',
    '   • Time in hours (column C): 0.5, 0.25, 2.0, 1.0, 1.5',
    '   • Markup % (column F): 150%, 200%, 120%, 180%, 160% (enter as decimal: 1.5, 2.0, etc.)',
    '   • Quantity to Bring (column H): 12, 20, 8, 15, 10',
    '',
    '⚙️ STEP 2: Create formulas in column E (Total Cost):',
    '   Formula: =B2+(C2*D2)  [Material Cost + (Time × Hourly Rate)]',
    '   Copy this formula down for all 5 products',
    '',
    '⚙️ STEP 3: Create formulas in column G (Selling Price):',
    '   Formula: =E2*(1+F2)  [Total Cost × (1 + Markup%)]',
    '   Copy this formula down for all 5 products',
    '',
    '⚙️ STEP 4: Create formulas in column I (Potential Revenue):',
    '   Formula: =G2*H2  [Selling Price × Quantity]',
    '   Copy this formula down for all 5 products',
    '',
    '⚙️ STEP 5: Create summary formulas:',
    '   • B9: =SUM(E2:E6)*1  [total cost of all items]',
    '   • B10: =SUM(I2:I6)  [total revenue if 100% sells]',
    '   • B11: =SUM(I2:I6)*0.6  [total revenue if 60% sells]',
    '   • B12: =B11-B9  [profit = revenue - cost]',
    '',
    '🎨 STEP 6: Apply formatting:',
    '   • Format columns B, E, G, I as Currency ($ symbol)',
    '   • Format column F as Percentage (% symbol)',
    '',
    '💾 STEP 7: Save the file (Ctrl+S)',
]

for i, instruction in enumerate(instructions, start=15):
    ws.cell(row=i, column=1, value=instruction)

wb.save(sys.argv[1])
print(f"Pricing sheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_pricing_sheet.py
python3 /tmp/create_pricing_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Pricing sheet template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_pricing_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_pricing_task.log || true
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

echo "=== Craft Fair Pricing Sheet Task Setup Complete ==="
echo ""
echo "📋 Task Overview:"
echo "   You're preparing for a craft fair and need a pricing calculator"
echo ""
echo "🎯 Your Goal:"
echo "   1. Fill in cost/time data for 5 handmade products"
echo "   2. Create formulas to calculate costs, prices, and revenue"
echo "   3. Build a summary section with projections"
echo "   4. Apply proper formatting (currency & percentages)"
echo ""
echo "📁 File: /home/ga/Documents/Spreadsheets/craft_fair_pricing.xlsx"
echo ""
echo "💡 Tip: Scroll down in the spreadsheet to see detailed instructions!"