#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Custom Cake Order Timeline Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with order information
SHEET_PATH="$WORKSPACE_DIR/CakeOrders_RawInfo.xlsx"

cat > /tmp/create_cake_orders.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
import sys

wb = Workbook()
ws = wb.active
ws.title = "Order Details"

# Set column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 25
ws.column_dimensions['C'].width = 20
ws.column_dimensions['D'].width = 18
ws.column_dimensions['E'].width = 18
ws.column_dimensions['F'].width = 20
ws.column_dimensions['G'].width = 35

# Header styling
header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
header_font = Font(bold=True, color="FFFFFF", size=11)
thin_border = Border(
    left=Side(style='thin'),
    right=Side(style='thin'),
    top=Side(style='thin'),
    bottom=Side(style='thin')
)

# Add title
ws['A1'] = "WEEKEND CUSTOM CAKE ORDERS - PRODUCTION PLANNING"
ws['A1'].font = Font(bold=True, size=14)
ws.merge_cells('A1:G1')

# Add headers
headers = ["Order", "Item", "Delivery/Pickup", "Baking Time", "Cooling Time", "Decorating Time", "Notes"]
for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=3, column=col_idx)
    cell.value = header
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal='center', vertical='center')
    cell.border = thin_border

# Order A: Wedding cake (3 tiers)
ws['A4'] = "A"
ws['B4'] = "Wedding cake (3 tiers)"
ws['C4'] = "Saturday 2:00 PM"
ws['D4'] = "3 hours total"
ws['E4'] = "4 hours minimum"
ws['F4'] = "5 hours"
ws['G4'] = "Each tier: 1hr bake. Needs fridge space for cooling."

# Order B: Graduation sheet cake
ws['A5'] = "B"
ws['B5'] = "Graduation sheet cake"
ws['C5'] = "Saturday 11:00 AM"
ws['D5'] = "1.5 hours"
ws['E5'] = "3 hours minimum"
ws['F5'] = "2 hours"
ws['G5'] = "EARLIEST deadline! Can decorate Friday night if baked early."

# Order C: Birthday cupcakes
ws['A6'] = "C"
ws['B6'] = "Birthday cupcakes (4 dozen)"
ws['C6'] = "Saturday 4:00 PM"
ws['D6'] = "45 min × 2 batches"
ws['E6'] = "1.5 hours"
ws['F6'] = "1.5 hours"
ws['G6'] = "Two separate oven batches needed (2 dozen per batch)."

# Apply borders to data rows
for row in range(4, 7):
    for col in range(1, 8):
        ws.cell(row=row, column=col).border = thin_border

# Add constraints section
ws['A8'] = "CONSTRAINTS & SCHEDULING NOTES:"
ws['A8'].font = Font(bold=True, size=12, color="C00000")
ws.merge_cells('A8:G8')

ws['A9'] = "• Oven available: 6:00 AM - 11:00 PM daily (only ONE item can bake at a time!)"
ws['A10'] = "• Fridge space: Can fit 2 cake tiers at once for cooling"
ws['A11'] = "• Buttercream prep: 1 hour (make all at once Thursday evening, store in fridge)"
ws['A12'] = "• Must sleep: Thursday 11 PM - 6 AM, Friday 11 PM - 6 AM"
ws['A13'] = "• Assembly for wedding cake: Must happen AFTER all tiers have cooled (included in decorating time)"
ws['A14'] = "• Buffer time: Add 30-60 min before each deadline for transport prep & boxing"

for row in range(9, 15):
    ws.merge_cells(f'A{row}:G{row}')
    ws.cell(row=row, column=1).alignment = Alignment(wrap_text=True, vertical='top')

# Add task instructions
ws['A16'] = "YOUR TASK:"
ws['A16'].font = Font(bold=True, size=12, color="00B050")
ws.merge_cells('A16:G16')

ws['A17'] = "1. Create a NEW SHEET called 'Production Timeline'"
ws['A18'] = "2. Work BACKWARD from each delivery/pickup deadline"
ws['A19'] = "3. Schedule: Decorating/Assembly → Cooling → Baking for each order"
ws['A20'] = "4. CRITICAL: Ensure NO oven conflicts (only one bake at a time)"
ws['A21'] = "5. Show hour-by-hour schedule from Thursday through Saturday"
ws['A22'] = "6. Mark which order each task belongs to (A, B, or C)"
ws['A23'] = "7. Indicate OVEN FREE vs OVEN BUSY periods"
ws['A24'] = "8. Save the file as: CakeOrders_ProductionTimeline.xlsx"

for row in range(17, 25):
    ws.merge_cells(f'A{row}:G{row}')
    ws.cell(row=row, column=1).alignment = Alignment(wrap_text=True, vertical='top')

# Add example timeline structure hint
ws['A26'] = "TIMELINE STRUCTURE EXAMPLE:"
ws['A26'].font = Font(bold=True, size=11, italic=True)
ws.merge_cells('A26:G26')

example_headers = ["Day", "Time", "Task Description", "Order", "Status", "Notes"]
for col_idx, header in enumerate(example_headers, start=1):
    if col_idx <= 6:
        cell = ws.cell(row=27, column=col_idx)
        cell.value = header
        cell.font = Font(italic=True)
        cell.border = thin_border

ws['A28'] = "Thursday"
ws['B28'] = "6:00 PM"
ws['C28'] = "Prep all buttercream"
ws['D28'] = "All"
ws['E28'] = "OVEN FREE"
ws['F28'] = "Takes 1 hour, store in fridge"

ws['A29'] = "Friday"
ws['B29'] = "6:00 PM"
ws['C29'] = "Bake graduation cake"
ws['D29'] = "B"
ws['E29'] = "OVEN BUSY"
ws['F29'] = "1.5 hours, finishes 7:30 PM"

for row in range(28, 30):
    for col in range(1, 7):
        ws.cell(row=row, column=col).border = thin_border
        ws.cell(row=row, column=col).font = Font(italic=True, size=9)

wb.save(sys.argv[1])
print(f"Cake order spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_cake_orders.py
python3 /tmp/create_cake_orders.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Cake order spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_cake_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_cake_task.log || true
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

echo "=== Custom Cake Order Timeline Task Setup Complete ==="
echo "📝 Scenario:"
echo "  You run a home bakery and have THREE large orders for this Saturday:"
echo "  - Order A: 3-tier wedding cake (delivery: Saturday 2:00 PM)"
echo "  - Order B: Graduation sheet cake (pickup: Saturday 11:00 AM) [EARLIEST!]"
echo "  - Order C: Birthday cupcakes, 4 dozen (pickup: Saturday 4:00 PM)"
echo ""
echo "⚠️  CRITICAL CONSTRAINT: You have only ONE oven!"
echo ""
echo "📋 Your Task:"
echo "  1. Create a new sheet: 'Production Timeline'"
echo "  2. Work backward from each deadline"
echo "  3. Schedule baking → cooling → decorating for each order"
echo "  4. Ensure NO oven time conflicts"
echo "  5. Show hour-by-hour schedule (Thursday-Saturday)"
echo "  6. Save as: CakeOrders_ProductionTimeline.xlsx"
echo ""
echo "💡 Tip: Order B has the earliest deadline (11 AM) - plan that first!"