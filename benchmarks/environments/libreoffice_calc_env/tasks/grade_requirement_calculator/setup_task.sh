#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Grade Requirement Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the grade calculation spreadsheet using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties, ParagraphProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencySymbol
from decimal import Decimal

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create styles for better formatting
bold_style = Style(name="Bold", family="paragraph")
bold_props = TextProperties(fontweight="bold")
bold_style.addElement(bold_props)
doc.styles.addElement(bold_style)

# Add main sheet
table = Table(name="Grade Calculator")
doc.spreadsheet.addElement(table)

def add_text_cell(row, text, bold=False):
    """Add a text cell to a row"""
    cell = TableCell(valuetype="string")
    p = P(text=str(text))
    if bold:
        p.setAttribute("stylename", "Bold")
    cell.addElement(p)
    row.addElement(cell)
    return cell

def add_number_cell(row, value):
    """Add a number cell to a row"""
    cell = TableCell(valuetype="float", value=str(value))
    p = P(text=str(value))
    cell.addElement(p)
    row.addElement(cell)
    return cell

def add_empty_cell(row):
    """Add an empty cell to a row"""
    cell = TableCell()
    row.addElement(cell)
    return cell

def add_formula_cell(row, formula):
    """Add a cell with a formula"""
    cell = TableCell(valuetype="float", formula=formula)
    row.addElement(cell)
    return cell

# Row 1: Title
row = TableRow()
add_text_cell(row, "Statistics 201 - Grade Calculator", bold=True)
add_empty_cell(row)
add_empty_cell(row)
add_empty_cell(row)
table.addElement(row)

# Row 2: Target grade
row = TableRow()
add_text_cell(row, "Target Grade:", bold=True)
add_text_cell(row, "87%")
add_text_cell(row, "(B+)")
add_empty_cell(row)
table.addElement(row)

# Row 3: Empty
row = TableRow()
for _ in range(4):
    add_empty_cell(row)
table.addElement(row)

# Row 4: Headers
row = TableRow()
add_text_cell(row, "Category", bold=True)
add_text_cell(row, "Weight", bold=True)
add_text_cell(row, "Current Score", bold=True)
add_text_cell(row, "Notes", bold=True)
table.addElement(row)

# Row 5: Homework
row = TableRow()
add_text_cell(row, "Homework")
add_text_cell(row, "25%")
add_text_cell(row, "[Calculate Average - Drop Lowest]")
add_text_cell(row, "7 assignments, drop lowest")
table.addElement(row)

# Row 6: Quizzes
row = TableRow()
add_text_cell(row, "Quizzes")
add_text_cell(row, "15%")
add_text_cell(row, "[Calculate Average]")
add_text_cell(row, "5 quizzes")
table.addElement(row)

# Row 7: Midterm
row = TableRow()
add_text_cell(row, "Midterm Exam")
add_text_cell(row, "20%")
add_number_cell(row, 82)
add_text_cell(row, "Completed")
table.addElement(row)

# Row 8: Project
row = TableRow()
add_text_cell(row, "Project")
add_text_cell(row, "15%")
add_text_cell(row, "Not yet submitted")
add_empty_cell(row)
table.addElement(row)

# Row 9: Final Exam
row = TableRow()
add_text_cell(row, "Final Exam")
add_text_cell(row, "25%")
add_text_cell(row, "Not yet taken")
add_empty_cell(row)
table.addElement(row)

# Row 10: Empty
row = TableRow()
for _ in range(4):
    add_empty_cell(row)
table.addElement(row)

# Row 11: Current Weighted Grade
row = TableRow()
add_text_cell(row, "Current Weighted Grade:", bold=True)
add_text_cell(row, "[FORMULA NEEDED]")
add_text_cell(row, "(from completed work only)")
add_empty_cell(row)
table.addElement(row)

# Row 12: Empty
row = TableRow()
for _ in range(4):
    add_empty_cell(row)
table.addElement(row)

# Row 13: Scenario Analysis Header
row = TableRow()
add_text_cell(row, "Scenario Analysis", bold=True)
add_empty_cell(row)
add_empty_cell(row)
add_empty_cell(row)
table.addElement(row)

# Row 14: Scenario 1
row = TableRow()
add_text_cell(row, "If Project Score =")
add_number_cell(row, 90)
add_text_cell(row, "Required Final Score:")
add_text_cell(row, "[FORMULA NEEDED]")
table.addElement(row)

# Row 15: Scenario 2
row = TableRow()
add_text_cell(row, "If Project Score =")
add_number_cell(row, 85)
add_text_cell(row, "Required Final Score:")
add_text_cell(row, "[FORMULA NEEDED]")
table.addElement(row)

# Row 16: Scenario 3
row = TableRow()
add_text_cell(row, "If Project Score =")
add_number_cell(row, 80)
add_text_cell(row, "Required Final Score:")
add_text_cell(row, "[FORMULA NEEDED]")
table.addElement(row)

# Add Assignment Details sheet
details_table = Table(name="Assignment Details")
doc.spreadsheet.addElement(details_table)

# Header row
row = TableRow()
add_text_cell(row, "Assignment", bold=True)
add_text_cell(row, "Score", bold=True)
add_text_cell(row, "Max Points", bold=True)
add_text_cell(row, "Percentage", bold=True)
details_table.addElement(row)

# Homework assignments (5 completed, 2 blank)
homework_scores = [
    ("HW 1", 45, 50, 90),
    ("HW 2", 38, 50, 76),
    ("HW 3", 42, 50, 84),
    ("HW 4", 35, 50, 70),
    ("HW 5", 48, 50, 96),
    ("HW 6", None, 50, None),
    ("HW 7", None, 50, None),
]

for hw_name, score, max_pts, pct in homework_scores:
    row = TableRow()
    add_text_cell(row, hw_name)
    if score is not None:
        add_number_cell(row, score)
        add_number_cell(row, max_pts)
        add_number_cell(row, pct)
    else:
        add_empty_cell(row)
        add_number_cell(row, max_pts)
        add_empty_cell(row)
    details_table.addElement(row)

# Quiz assignments (4 completed, 1 blank)
quiz_scores = [
    ("Quiz 1", 18, 20, 90),
    ("Quiz 2", 17, 20, 85),
    ("Quiz 3", 16, 20, 80),
    ("Quiz 4", 19, 20, 95),
    ("Quiz 5", None, 20, None),
]

for quiz_name, score, max_pts, pct in quiz_scores:
    row = TableRow()
    add_text_cell(row, quiz_name)
    if score is not None:
        add_number_cell(row, score)
        add_number_cell(row, max_pts)
        add_number_cell(row, pct)
    else:
        add_empty_cell(row)
        add_number_cell(row, max_pts)
        add_empty_cell(row)
    details_table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/grade_calculator.ods")
print("✅ Created grade_calculator.ods successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/grade_calculator.ods
sudo chmod 666 /home/ga/Documents/grade_calculator.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/grade_calculator.ods > /tmp/calc_grade_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_grade_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Navigate to cell C5 (where homework average should be calculated)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key --delay 100 Down Down Down Down
safe_xdotool ga :1 key --delay 100 Right Right
sleep 0.2

echo "=== Grade Calculator Task Setup Complete ==="
echo "📝 Task: Calculate required scores for target grade"
echo "📊 Target: 87% (B+)"
echo "💡 Instructions:"
echo "  1. Calculate homework average (drop lowest) in Cell C5"
echo "  2. Calculate quiz average in Cell C6"
echo "  3. Calculate current weighted grade in Cell B11"
echo "  4. Calculate required final scores in Column D (rows 14-16)"
echo ""
echo "Key formulas needed:"
echo "  - Homework (drop lowest): =(SUM(range)-MIN(range))/(COUNT(range)-1)"
echo "  - Current grade: weighted average of completed categories"
echo "  - Required final: solve for unknown in weighted average equation"