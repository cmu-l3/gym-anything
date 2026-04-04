#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Classroom Seating Chart Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the student roster text file
ROSTER_PATH="$WORKSPACE_DIR/student_roster.txt"

cat > "$ROSTER_PATH" << 'EOF'
STUDENT ROSTER - PERIOD 3 ENGLISH - MS. RODRIGUEZ

Marcus Chen - IEP, preferential seating FRONT, strong reader
Aisha Williams - 504 plan, hearing impaired RIGHT SIDE away from HVAC (left wall)
Jordan Blake - sep from Taylor M, creative thinker
Emma Kowalski - IEP front row, struggles with focus
Liam O'Brien - peer mentor, reliable
Sofia Martinez - sep from Jordan B, good leadership
Taylor Morrison - sep from Jordan B, impulsive
Kai Patel - average student
Zoe Thompson - anxiety, prefers NEAR DOOR (right side)
Nathan Drake - strong student, patient
Isabella Garcia - ELL support, bilingual peer nearby helpful
Carlos Mendez - ELL support, Spanish speaker
Ava Johnson - behavior watch, sep from Marcus C
Ethan Brown - wheelchair accessible, END OF ROW or NEAR DOOR
Mia Anderson - gifted, gets bored easily
Noah Wilson - class clown, needs structure
Olivia Taylor - reliable, artistic
Mason Lee - new student, no data yet
Harper Scott - shy, needs encouragement
Logan Martinez - attention seeking, sep from Noah W
Ella Davis - strong student
Jackson Young - IEP math only, English is strength
Amelia White - reliable
Lucas Harris - behavior watch last semester
Grace Kim - student council, responsible
Chloe Robinson - struggles socially
Ryan Lewis - athletic, kinesthetic learner
Lily Walker - organized, helpful

ROOM LAYOUT NOTES:
- 6 rows (A-F) by 5 columns (1-5)
- Row A is front (by board)
- HVAC unit is loud on left wall (column 1 side)
- Door is on right rear (near column 5, row F)
- Desk B5 is MISSING (broken desk removed)
- Need wheelchair space at end of row or near door

INSTRUCTIONS:
1. Place students in the grid according to their needs
2. Marcus Chen and Emma Kowalski MUST be in Row A (front row - IEP requirement)
3. Aisha Williams MUST be in column 4 or 5 (right side, away from HVAC)
4. Ethan Brown MUST be in column 5 (wheelchair accessible - end of row/near door)
5. Keep Jordan Blake away from both Taylor Morrison and Sofia Martinez (not adjacent)
6. Keep Marcus Chen away from Ava Johnson (behavior conflict - not adjacent)
7. Use color-coding (cell background colors) to highlight IEP/504 students
8. All 27 students must be placed (28 desks - 1 empty at B5)
EOF

chown ga:ga "$ROSTER_PATH"
echo "✅ Student roster created at: $ROSTER_PATH"

# Create the seating template spreadsheet
SHEET_PATH="$WORKSPACE_DIR/seating_template.xlsx"

cat > /tmp/create_seating_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.utils import get_column_letter
import sys

wb = Workbook()
ws = wb.active
ws.title = "Seating Chart"

# Define the grid structure: 6 rows (A-F) by 5 columns (1-5)
# Layout: Column A for row labels, Columns B-F for the 5 desk columns
ROWS = ['A', 'B', 'C', 'D', 'E', 'F']
COLS = [1, 2, 3, 4, 5]

# Set column widths
ws.column_dimensions['A'].width = 8  # Row label column
for col_num in range(1, 6):
    ws.column_dimensions[get_column_letter(col_num + 1)].width = 22

# Create header row with column numbers
ws['A1'] = "Row"
ws['A1'].font = Font(bold=True, size=11)
ws['A1'].alignment = Alignment(horizontal='center', vertical='center')

for col_idx, col_num in enumerate(COLS, start=2):
    cell = ws.cell(row=1, column=col_idx)
    cell.value = f"Column {col_num}"
    cell.font = Font(bold=True, size=11)
    cell.alignment = Alignment(horizontal='center', vertical='center')
    cell.fill = PatternFill(start_color="E0E0E0", end_color="E0E0E0", fill_type="solid")

# Define border style
thin_border = Border(
    left=Side(style='thin', color='000000'),
    right=Side(style='thin', color='000000'),
    top=Side(style='thin', color='000000'),
    bottom=Side(style='thin', color='000000')
)

# Create grid with row labels
for row_idx, row_letter in enumerate(ROWS, start=2):
    # Row label
    label_cell = ws.cell(row=row_idx, column=1)
    label_cell.value = row_letter
    label_cell.font = Font(bold=True, size=12)
    label_cell.alignment = Alignment(horizontal='center', vertical='center')
    label_cell.fill = PatternFill(start_color="E0E0E0", end_color="E0E0E0", fill_type="solid")
    
    # Empty cells for student names
    for col_idx, col_num in enumerate(COLS, start=2):
        cell = ws.cell(row=row_idx, column=col_idx)
        cell.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)
        cell.border = thin_border
        cell.font = Font(size=11)
        
        # Mark B5 as empty (row B = row_idx 3, col 5 = col_idx 6)
        if row_letter == 'B' and col_num == 5:
            cell.value = "EMPTY\n(No Desk)"
            cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")
            cell.font = Font(italic=True, size=10, color="666666")

# Set row heights
ws.row_dimensions[1].height = 25
for row in range(2, 8):
    ws.row_dimensions[row].height = 60

# Add instructions in a separate area
instructions_row = 10
ws[f'A{instructions_row}'] = "INSTRUCTIONS:"
ws[f'A{instructions_row}'].font = Font(bold=True, size=12)

instructions = [
    "1. Read student_roster.txt for student names and constraints",
    "2. Place each student name in the appropriate cell (Row A-F, Column 1-5)",
    "3. Ensure IEP students (Marcus Chen, Emma Kowalski) are in Row A (front)",
    "4. Ensure Aisha Williams is in Column 4 or 5 (hearing accommodation)",
    "5. Ensure Ethan Brown is in Column 5 (wheelchair accessible)",
    "6. Keep conflicting students separated (not adjacent, including diagonally)",
    "7. Apply background colors to highlight IEP/504 students (at least 3 cells)",
    "8. Save when complete (Ctrl+S)"
]

for i, instruction in enumerate(instructions, start=instructions_row + 1):
    ws[f'A{i}'] = instruction
    ws[f'A{i}'].font = Font(size=10)
    ws.merge_cells(f'A{i}:F{i}')

wb.save(sys.argv[1])
print(f"Seating template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_seating_sheet.py
python3 /tmp/create_seating_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Seating template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the seating template
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_seating_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_seating_task.log || true
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

echo "=== Classroom Seating Chart Task Setup Complete ==="
echo ""
echo "📋 Task Overview:"
echo "  Create a classroom seating chart for 28 students (27 students + 1 empty desk)"
echo ""
echo "📝 Key Requirements:"
echo "  ✓ Read student_roster.txt for student names and constraints"
echo "  ✓ Place Marcus Chen and Emma Kowalski in Row A (IEP - front row)"
echo "  ✓ Place Aisha Williams in Column 4 or 5 (hearing impaired - right side)"
echo "  ✓ Place Ethan Brown in Column 5 (wheelchair accessible)"
echo "  ✓ Separate Jordan Blake from Taylor Morrison and Sofia Martinez"
echo "  ✓ Separate Marcus Chen from Ava Johnson"
echo "  ✓ Apply color-coding to highlight special needs students"
echo "  ✓ Save when complete (Ctrl+S)"
echo ""
echo "📂 Files:"
echo "  • Seating template: $SHEET_PATH"
echo "  • Student roster: $ROSTER_PATH"