#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Gradebook Weighted Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install Python ODF library if not present
# apt-get update -qq && apt-get install -y python3-odf > /dev/null 2>&1 || true

# Create gradebook template ODS file using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, ParagraphProperties
from odf.number import NumberStyle, Number, Text as NumberText
import random

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create a sheet
table = Table(name="Grades")
doc.spreadsheet.addElement(table)

# Student names (12 students for realistic classroom)
students = [
    "Emma Johnson",
    "Liam Martinez",
    "Olivia Chen",
    "Noah Williams",
    "Ava Patel",
    "Elijah Rodriguez",
    "Sophia Anderson",
    "Mason Thompson",
    "Isabella Davis",
    "Lucas Garcia",
    "Mia Wilson",
    "Ethan Brown"
]

# Headers row
header_row = TableRow()
headers = [
    "Student Name",  # A
    "Test 1", "Test 2", "Test 3",  # B-D
    "HW 1", "HW 2", "HW 3", "HW 4",  # E-H
    "Quiz 1", "Quiz 2", "Quiz 3", "Quiz 4",  # I-L
    "Participation",  # M
    "Test Avg", "HW Avg", "Quiz Avg", "Participation",  # N-Q (to be filled)
    "Final Grade (%)", "Letter Grade"  # R-S (to be filled)
]

for header_text in headers:
    cell = TableCell()
    p = P(text=header_text)
    cell.addElement(p)
    header_row.addElement(cell)

table.addElement(header_row)

# Grade data - create realistic distributions with some missing values
# Performance profiles: high (90s), medium-high (80s), medium (70s), low (60s), struggling (50s)
random.seed(42)  # For reproducibility

def generate_score(base, variance, missing_chance=0.1):
    """Generate a score with some randomness and occasional missing values"""
    if random.random() < missing_chance:
        return None  # Missing assignment
    return max(0, min(100, base + random.randint(-variance, variance)))

# Student performance profiles (base score, variance)
profiles = [
    (95, 3),   # Emma - excellent
    (88, 5),   # Liam - good
    (92, 4),   # Olivia - excellent
    (75, 6),   # Noah - average
    (82, 5),   # Ava - good
    (68, 7),   # Elijah - below average
    (89, 4),   # Sophia - good (near boundary)
    (78, 6),   # Mason - average
    (85, 5),   # Isabella - good
    (72, 6),   # Lucas - average
    (91, 4),   # Mia - excellent
    (65, 8),   # Ethan - struggling
]

for student_idx, student_name in enumerate(students):
    row = TableRow()
    
    # Student name
    name_cell = TableCell(valuetype="string")
    name_cell.addElement(P(text=student_name))
    row.addElement(name_cell)
    
    base, variance = profiles[student_idx]
    
    # Test scores (B-D) - 3 tests
    for _ in range(3):
        score = generate_score(base, variance, missing_chance=0.05)
        cell = TableCell()
        if score is not None:
            cell.setAttribute("valuetype", "float")
            cell.setAttribute("value", str(score))
            cell.addElement(P(text=str(score)))
        row.addElement(cell)
    
    # Homework scores (E-H) - 4 homeworks
    for _ in range(4):
        score = generate_score(base, variance + 5, missing_chance=0.15)  # More variance, more missing
        cell = TableCell()
        if score is not None:
            cell.setAttribute("valuetype", "float")
            cell.setAttribute("value", str(score))
            cell.addElement(P(text=str(score)))
        row.addElement(cell)
    
    # Quiz scores (I-L) - 4 quizzes (one will be dropped)
    for _ in range(4):
        score = generate_score(base, variance + 8, missing_chance=0.08)
        cell = TableCell()
        if score is not None:
            cell.setAttribute("valuetype", "float")
            cell.setAttribute("value", str(score))
            cell.addElement(P(text=str(score)))
        row.addElement(cell)
    
    # Participation (M) - single score, rarely missing
    participation = generate_score(base, variance - 2, missing_chance=0.02)
    cell = TableCell()
    if participation is not None:
        cell.setAttribute("valuetype", "float")
        cell.setAttribute("value", str(participation))
        cell.addElement(P(text=str(participation)))
    row.addElement(cell)
    
    # Empty cells for calculated columns (N-S)
    for _ in range(6):
        row.addElement(TableCell())
    
    table.addElement(row)

# Add a few empty rows
for _ in range(5):
    row = TableRow()
    for _ in range(len(headers)):
        row.addElement(TableCell())
    table.addElement(row)

# Add grading scale reference at the bottom (row 20+)
for _ in range(2):  # Empty rows
    row = TableRow()
    for _ in range(len(headers)):
        row.addElement(TableCell())
    table.addElement(row)

# Grading scale header
scale_row = TableRow()
cell = TableCell(valuetype="string")
cell.addElement(P(text="GRADING SCALE"))
scale_row.addElement(cell)
for _ in range(len(headers) - 1):
    scale_row.addElement(TableCell())
table.addElement(scale_row)

# Scale details
scale_info = [
    ("Grade", "Min %", "Max %"),
    ("A", "90", "100"),
    ("B", "80", "89"),
    ("C", "70", "79"),
    ("D", "60", "69"),
    ("F", "0", "59"),
]

for scale_line in scale_info:
    row = TableRow()
    for item in scale_line:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=item))
        row.addElement(cell)
    for _ in range(len(headers) - 3):
        row.addElement(TableCell())
    table.addElement(row)

# Add grading policy explanation
for _ in range(1):
    row = TableRow()
    for _ in range(len(headers)):
        row.addElement(TableCell())
    table.addElement(row)

policy_row = TableRow()
cell = TableCell(valuetype="string")
cell.addElement(P(text="GRADING POLICY: Tests 40% | Homework 30% | Quizzes 20% (DROP LOWEST) | Participation 10%"))
policy_row.addElement(cell)
for _ in range(len(headers) - 1):
    policy_row.addElement(TableCell())
table.addElement(policy_row)

# Save the file
doc.save("/home/ga/Documents/gradebook_template.ods")
print("✅ Created gradebook template with 12 students")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/gradebook_template.ods
sudo chmod 666 /home/ga/Documents/gradebook_template.ods

# Launch LibreOffice Calc with the gradebook
echo "Launching LibreOffice Calc with gradebook template..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/gradebook_template.ods > /tmp/calc_gradebook_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_gradebook_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
fi

# Click on center of the screen to select current desktop
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

# Position cursor at cell N1 (first calculation column)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Gradebook Weighted Calculator Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Calculate final grades using the following steps:"
echo ""
echo "1. Column N (Test Avg): =AVERAGE(B2:D2)"
echo "2. Column O (HW Avg): =AVERAGE(E2:H2)"
echo "3. Column P (Quiz Avg - DROP LOWEST): =(SUM(I2:L2)-MIN(I2:L2))/(COUNT(I2:L2)-1)"
echo "4. Column Q (Participation): =M2"
echo "5. Column R (Final Grade): =(N2*0.40)+(O2*0.30)+(P2*0.20)+(Q2*0.10)"
echo "6. Column S (Letter Grade): =IF(R2>=90,\"A\",IF(R2>=80,\"B\",IF(R2>=70,\"C\",IF(R2>=60,\"D\",\"F\"))))"
echo ""
echo "Copy formulas down for all 12 students (rows 2-13)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"