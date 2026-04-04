#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Shelf Cut Optimizer Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with template
SHEET_PATH="$WORKSPACE_DIR/shelf_project.xlsx"

cat > /tmp/create_shelf_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
from openpyxl.styles.borders import Border, Side
import sys

wb = Workbook()
ws = wb.active
ws.title = "Cutting Plan"

# Set column widths
ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 18
ws.column_dimensions['D'].width = 30

# Title
ws['A1'] = 'FLOATING SHELF PROJECT - LUMBER CUT LIST'
ws['A1'].font = Font(bold=True, size=14, color="FFFFFF")
ws['A1'].fill = PatternFill(start_color="1F4E78", end_color="1F4E78", fill_type="solid")
ws.merge_cells('A1:D1')
ws['A1'].alignment = Alignment(horizontal='center', vertical='center')

# Section: Required Pieces
ws['A3'] = 'REQUIRED PIECES'
ws['A3'].font = Font(bold=True, size=12)
ws['A3'].fill = PatternFill(start_color="D9E1F2", end_color="D9E1F2", fill_type="solid")
ws.merge_cells('A3:C3')

ws['A4'] = 'Piece Description'
ws['B4'] = 'Length (inches)'
ws['C4'] = 'Quantity Needed'
for cell in ['A4', 'B4', 'C4']:
    ws[cell].font = Font(bold=True)
    ws[cell].fill = PatternFill(start_color="E7E6E6", end_color="E7E6E6", fill_type="solid")

# Required pieces data
ws['A5'] = 'Shelf Board'
ws['B5'] = 34
ws['C5'] = 3

ws['A6'] = 'Support Bracket'
ws['B6'] = 9
ws['C6'] = 6

ws['A7'] = 'Back Mounting Strip'
ws['B7'] = 32
ws['C7'] = 2

# Section: Constraints
ws['A9'] = 'CONSTRAINTS'
ws['A9'].font = Font(bold=True, size=12)
ws['A9'].fill = PatternFill(start_color="D9E1F2", end_color="D9E1F2", fill_type="solid")
ws.merge_cells('A9:C9')

ws['A10'] = 'Available board length:'
ws['B10'] = 96
ws['C10'] = 'inches (8 feet)'

ws['A11'] = 'Saw kerf per cut:'
ws['B11'] = 0.125
ws['C11'] = 'inches (blade width)'

# Instructions
ws['A13'] = 'INSTRUCTIONS'
ws['A13'].font = Font(bold=True, size=11, color="C00000")
ws.merge_cells('A13:D13')

ws['A14'] = 'Create a cutting plan below that:'
ws['A14'].font = Font(italic=True)
ws.merge_cells('A14:D14')

instructions = [
    '1. Shows which pieces come from which board (e.g., "Board 1: 34 + 34 + 9")',
    '2. Accounts for saw kerf - each cut wastes 0.125 inches',
    '3. Calculates total length used per board (pieces + kerf)',
    '4. Calculates waste per board',
    '5. Determines the MINIMUM number of boards needed to buy',
    '',
    'HINT: With 3 shelves (34"), 6 brackets (9"), and 2 strips (32"),',
    'you need total: (3×34) + (6×9) + (2×32) = 102 + 54 + 64 = 220 inches',
    'But remember: each piece requires a cut, so add kerf losses!'
]

row = 15
for instruction in instructions:
    ws[f'A{row}'] = instruction
    ws[f'A{row}'].font = Font(size=9)
    ws.merge_cells(f'A{row}:D{row}')
    row += 1

# Leave space for work
ws['A25'] = 'YOUR CUTTING PLAN (create below):'
ws['A25'].font = Font(bold=True, size=11)
ws['A25'].fill = PatternFill(start_color="FFF2CC", end_color="FFF2CC", fill_type="solid")
ws.merge_cells('A25:D25')

# Save
wb.save(sys.argv[1])
print(f"Spreadsheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_shelf_sheet.py
python3 /tmp/create_shelf_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_shelf_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_shelf_task.log || true
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

echo "=== Shelf Cut Optimizer Task Setup Complete ==="
echo "📝 Scenario:"
echo "  You're building floating shelves and need to figure out how many"
echo "  8-foot boards to buy and how to cut them efficiently."
echo ""
echo "📋 Required:"
echo "  - 3 shelf boards: 34 inches each"
echo "  - 6 support brackets: 9 inches each"
echo "  - 2 back strips: 32 inches each"
echo ""
echo "🔧 Constraints:"
echo "  - Boards are 96 inches (8 feet)"
echo "  - Each cut wastes 0.125 inches (saw kerf)"
echo ""
echo "✅ Goal:"
echo "  Design cutting plan, calculate waste, find minimum boards needed"
echo "  Save when complete (Ctrl+S)"