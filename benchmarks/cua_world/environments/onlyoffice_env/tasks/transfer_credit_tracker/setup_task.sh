#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Transfer Credit Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DOCS_DIR"

# Create the course data file that the agent will reference
COURSE_DATA_PATH="$DOCS_DIR/course_data.txt"

cat > "$COURSE_DATA_PATH" << 'EOF'
COMMUNITY COLLEGE TRANSCRIPT - MAYA RODRIGUEZ
=============================================

COMPLETED COURSES:
------------------
BIOL151 - Cell Biology | 4 credits | Grade: A
CHEM110 - General Chemistry I | 4 credits | Grade: B+
MATH210 - Calculus I | 4 credits | Grade: A-
ENGL101 - Composition | 3 credits | Grade: B
BIOL152 - Genetics Lab | 2 credits | Grade: A
PHYS105 - Intro Physics | 4 credits | Grade: C+
ARTS120 - Drawing Fundamentals | 3 credits | Grade: P (Pass/Fail)
COMM115 - Public Speaking | 3 credits | Grade: B-

TRANSFER EQUIVALENCY NOTES:
---------------------------
- BIOL151 transfers as BIOL201 (4 credits) ✓
- CHEM110 transfers as CHEM131 (4 credits) ✓
- MATH210 transfers as MATH141 (4 credits) ✓
- ENGL101 transfers as ENGL110 (3 credits) ✓
- BIOL152 transfers as BIOL210L (2 credits) ✓
- PHYS105 transfers but REDUCED to 3 credits (originally 4) ✓
- ARTS120 does NOT transfer (art elective not accepted) ✗
- COMM115 transfers as COMM101 (3 credits) ✓

MAJOR REQUIREMENTS (Biology):
-----------------------------
Major courses for GPA calculation:
- BIOL151 (Cell Biology)
- BIOL152 (Genetics Lab)
- CHEM110 (General Chemistry I)

GRADE SCALE:
-----------
A  = 4.0    B+ = 3.3    C+ = 2.3
A- = 3.7    B  = 3.0    C  = 2.0
            B- = 2.7    C- = 1.7

P/F courses do NOT count in GPA calculation.

TASK: Create a spreadsheet to analyze which courses transfer, 
calculate transfer GPA, and determine major GPA to see if Maya 
qualifies for competitive programs (requires 3.5+ major GPA).
EOF

chown ga:ga "$COURSE_DATA_PATH"

echo "✅ Course data created at: $COURSE_DATA_PATH"

# Create the initial spreadsheet with headers
SHEET_PATH="$WORKSPACE_DIR/transfer_analysis.xlsx"

cat > /tmp/create_transfer_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Transfer_Analysis"

# Create headers with formatting
headers = [
    "Course Code",
    "Course Name", 
    "Original Credits",
    "Grade",
    "Transfers?",
    "Transfer Credits",
    "Grade Points",
    "Quality Points",
    "Major Course?"
]

# Apply header formatting
header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
header_font = Font(bold=True, color="FFFFFF")

for col_num, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_num)
    cell.value = header
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal="center", vertical="center")

# Set column widths for better readability
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 22
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 8
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 15
ws.column_dimensions['G'].width = 12
ws.column_dimensions['H'].width = 14
ws.column_dimensions['I'].width = 14

# Add instruction text below headers
ws['A12'] = "Summary Calculations:"
ws['A12'].font = Font(bold=True, size=11)

ws['A13'] = "Total Original Credits:"
ws['A14'] = "Total Transfer Credits:"
ws['A15'] = "Overall Transfer GPA:"
ws['A16'] = "Major GPA (Biology):"

# Format instruction cells
for row in [13, 14, 15, 16]:
    ws[f'A{row}'].font = Font(italic=True)

wb.save(sys.argv[1])
print(f"Transfer analysis spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_transfer_sheet.py
python3 /tmp/create_transfer_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_transfer_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_transfer_task.log || true
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

# Also open the course data file in a text editor for easy reference
echo "Opening course data file for reference..."
su - ga -c "DISPLAY=:1 gedit '$COURSE_DATA_PATH' > /tmp/gedit_course_data.log 2>&1 &"
sleep 2

# Position the text editor window to the side if possible
su - ga -c "DISPLAY=:1 wmctrl -r 'course_data.txt' -e 0,50,50,700,900" 2>/dev/null || true

echo "=== Transfer Credit Tracker Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "=================================================="
echo "A text file with course data is open in gedit for reference."
echo ""
echo "Your goal: Create a transfer credit analysis spreadsheet"
echo ""
echo "Required Data Entry (Rows 2-9):"
echo "  - Enter all 8 courses from the transcript"
echo "  - Fill in: Course Code, Name, Original Credits, Grade"
echo "  - Mark transfer status (Yes/No)"
echo "  - Enter transfer credits (watch for PHYS105 reduction & ARTS120)"
echo "  - Calculate grade points (A=4.0, A-=3.7, B+=3.3, B=3.0, etc.)"
echo "  - Calculate quality points (Transfer Credits × Grade Points)"
echo "  - Mark major courses (BIOL151, BIOL152, CHEM110)"
echo ""
echo "Required Calculations (Around Rows 13-16):"
echo "  - Total Original Credits (should = 27)"
echo "  - Total Transfer Credits (should = 24)"
echo "  - Overall Transfer GPA (should ≈ 3.48)"
echo "  - Major GPA (should ≈ 3.70)"
echo ""
echo "Key Points:"
echo "  • ARTS120 (P/F) does NOT transfer and has no grade points"
echo "  • PHYS105 transfers but reduced: 4 credits → 3 credits"
echo "  • Only graded, transferring courses count in GPA"
echo "  • Quality Points = Transfer Credits × Grade Points"
echo ""
echo "When done: Save with Ctrl+S"
echo "=================================================="