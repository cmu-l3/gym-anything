#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Weighted Grade Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with student gradebook data
cat > /home/ga/Documents/gradebook.csv << 'CSVEOF'
Student Name,Homework,Midterm,Final Exam,Final Grade (%),Letter Grade
Alice Johnson,85,92,88,,
Bob Smith,78,81,85,,
Carol Williams,92,95,91,,
David Brown,65,70,68,,
Emma Davis,88,84,90,,
Frank Miller,72,75,78,,
Grace Wilson,95,98,96,,
Henry Moore,58,62,55,,
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/gradebook.csv
sudo chmod 666 /home/ga/Documents/gradebook.csv

echo "✅ Created gradebook.csv with student data"

# Convert CSV to ODS using LibreOffice headless mode
echo "Converting CSV to ODS format..."
su - ga -c "DISPLAY=:1 libreoffice --headless --convert-to ods /home/ga/Documents/gradebook.csv --outdir /home/ga/Documents" 2>&1 | tee /tmp/convert_gradebook.log || true
sleep 2

# Check if conversion succeeded
if [ ! -f "/home/ga/Documents/gradebook.ods" ]; then
    echo "⚠️ ODS conversion failed, will work with CSV"
    # Create a minimal ODS file using Python
    python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet
table = Table(name="Sheet1")
doc.spreadsheet.addElement(table)

# Add header row
header_data = ["Student Name", "Homework", "Midterm", "Final Exam", "Final Grade (%)", "Letter Grade"]
header_row = TableRow()
for header in header_data:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
table.addElement(header_row)

# Add student data
students = [
    ["Alice Johnson", 85, 92, 88],
    ["Bob Smith", 78, 81, 85],
    ["Carol Williams", 92, 95, 91],
    ["David Brown", 65, 70, 68],
    ["Emma Davis", 88, 84, 90],
    ["Frank Miller", 72, 75, 78],
    ["Grace Wilson", 95, 98, 96],
    ["Henry Moore", 58, 62, 55]
]

for student in students:
    row = TableRow()
    # Name
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=student[0]))
    row.addElement(cell)
    # Scores
    for score in student[1:]:
        cell = TableCell(valuetype="float", value=str(score))
        cell.addElement(P(text=str(score)))
        row.addElement(cell)
    # Empty cells for Final Grade (%) and Letter Grade
    for _ in range(2):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Add empty rows
for _ in range(10):
    row = TableRow()
    for _ in range(6):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save
doc.save("/home/ga/Documents/gradebook.ods")
print("Created ODS file successfully")
PYEOF
    sudo chown ga:ga /home/ga/Documents/gradebook.ods
    sudo chmod 666 /home/ga/Documents/gradebook.ods
fi

# Launch LibreOffice Calc with the gradebook
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/gradebook.ods > /tmp/calc_grade_task.log 2>&1 &"

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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Weighted Grade Calculator Task Setup Complete ==="
echo ""
echo "📋 GRADING SCHEME:"
echo "  • Homework (Column B): 30% of final grade"
echo "  • Midterm (Column C): 30% of final grade"
echo "  • Final Exam (Column D): 40% of final grade"
echo ""
echo "📝 INSTRUCTIONS:"
echo "  1. In cell E2, create weighted grade formula:"
echo "     =(B2*0.30)+(C2*0.30)+(D2*0.40)"
echo "  2. Copy formula down to all students (E2:E9)"
echo "  3. In cell F2, create letter grade formula:"
echo "     =IF(E2>=90,\"A\",IF(E2>=80,\"B\",IF(E2>=70,\"C\",IF(E2>=60,\"D\",\"F\"))))"
echo "  4. Copy formula down to all students (F2:F9)"
echo ""
echo "🎯 LETTER GRADE SCALE:"
echo "  A: ≥90%  |  B: 80-89%  |  C: 70-79%  |  D: 60-69%  |  F: <60%"