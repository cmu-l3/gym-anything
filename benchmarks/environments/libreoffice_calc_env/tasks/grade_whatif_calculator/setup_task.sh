#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Grade Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the gradebook template using Python with ODF library
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, Number, Text as NumberText
import odf.number

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Grades"
table = Table(name="Grades")

# Helper function to create a row with cells
def make_row(values):
    row = TableRow()
    for value in values:
        cell = TableCell()
        if value is not None:
            if isinstance(value, (int, float)):
                cell.setAttrNS(odf.namespaces.OFFICENS, 'value-type', 'float')
                cell.setAttrNS(odf.namespaces.OFFICENS, 'value', str(value))
            elif isinstance(value, str) and value.startswith('='):
                # Formula
                cell.setAttrNS(odf.namespaces.OFFICENS, 'value-type', 'float')
                cell.setAttrNS(odf.namespaces.TABLENS, 'formula', value)
            p = P(text=str(value))
            cell.addElement(p)
        row.addElement(cell)
    return row

# Build the gradebook structure
rows_data = [
    ["MATH 101 Grade Calculator", None],  # Row 1: Title
    [None, None],  # Row 2: Empty
    ["Homework (20%)", None],  # Row 3: Section header
    ["HW1:", 95],  # Row 4
    ["HW2:", 88],  # Row 5
    ["HW3:", 92],  # Row 6
    ["HW4:", 100],  # Row 7
    ["HW5:", 85],  # Row 8
    ["Homework Average:", "=AVERAGE(B4:B8)"],  # Row 9
    [None, None],  # Row 10: Empty
    ["Quizzes (20%)", None],  # Row 11: Section header
    ["Q1:", 82],  # Row 12
    ["Q2:", 90],  # Row 13
    ["Q3:", 78],  # Row 14
    ["Q4:", 88],  # Row 15
    ["Quiz Average:", "=AVERAGE(B12:B15)"],  # Row 16
    [None, None],  # Row 17: Empty
    ["Midterm Exam (25%):", 84],  # Row 18
    ["Final Exam (35%):", None],  # Row 19 - empty for student
    [None, None],  # Row 20: Empty
    ["Current Grade (before final):", None],  # Row 21 - STUDENT FILLS THIS
    ["Target Final Grade:", 90],  # Row 22
    ["Needed on Final Exam:", None],  # Row 23 - STUDENT FILLS THIS
]

# Add rows to table
for row_data in rows_data:
    table.addElement(make_row(row_data))

# Add some empty rows at the end
for _ in range(10):
    table.addElement(make_row([None] * 10))

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/my_grades.ods")
print("✅ Created gradebook template successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/my_grades.ods
sudo chmod 666 /home/ga/Documents/my_grades.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/my_grades.ods > /tmp/calc_grade_task.log 2>&1 &"

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

# Position cursor at cell B21 (Current Grade formula cell)
echo "Positioning cursor at formula cell..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Navigate to B21 using Ctrl+G (Go To dialog)
safe_xdotool ga :1 key ctrl+g
sleep 0.5
safe_xdotool ga :1 type "B21"
sleep 0.3
safe_xdotool ga :1 key Return
sleep 0.3

echo "=== Grade Calculator Task Setup Complete ==="
echo ""
echo "📚 Scenario: You're a student in MATH 101. It's Week 10 of the semester."
echo "📊 Your grades so far:"
echo "   • Homework (20%): 5 assignments completed → Average in cell B9"
echo "   • Quizzes (20%): 4 quizzes completed → Average in cell B16"
echo "   • Midterm (25%): Score of 84"
echo "   • Final Exam (35%): Not yet taken"
echo ""
echo "🎯 Your goal: Achieve a 90% final grade to maintain your scholarship"
echo ""
echo "✏️  Your task:"
echo "   1. In cell B21: Calculate your CURRENT GRADE (weighted average of completed work)"
echo "      Formula hint: =(B9*0.2)+(B16*0.2)+(B18*0.25)"
echo "   2. In cell B23: Calculate the score you NEED on the final exam"
echo "      Formula hint: =(B22-B21)/0.35"
echo ""
echo "💡 Tip: Use cell references (B9, B16, etc.) not hardcoded numbers!"
echo "🔍 Expected results: Current grade ~56%, Needed on final ~96%"