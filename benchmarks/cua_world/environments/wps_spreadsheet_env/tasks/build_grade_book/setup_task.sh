#!/bin/bash
echo "=== Setting up build_grade_book task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

FILE_PATH="/home/ga/Documents/math_grades.xlsx"
rm -f "$FILE_PATH" 2>/dev/null || true

# Generate the grade book using a subset of the real UCI Student Performance dataset
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill

# Real student records derived and scaled from the UCI dataset
uci_data = [
    (25, 30, 30, 30), (25, 30, 25, 30), (35, 30, 40, 50), (75, 45, 70, 75),
    (30, 30, 50, 50), (75, 30, 75, 75), (55, 30, 60, 55), (30, 30, 25, 30),
    (75, 30, 90, 95), (70, 30, 75, 75), (50, 30, 40, 45), (50, 45, 60, 60),
    (70, 15, 70, 70), (50, 30, 50, 55), (70, 45, 80, 80), (70, 15, 70, 70),
    (65, 45, 70, 70), (40, 30, 50, 50), (30, 15, 25, 25), (40, 15, 50, 50),
    (65, 30, 70, 75), (60, 30, 75, 75), (75, 30, 75, 80), (65, 30, 65, 60),
    (50, 45, 45, 40), (30, 15, 45, 40), (60, 15, 60, 55), (75, 15, 80, 75),
    (55, 30, 55, 55), (50, 30, 60, 55), (45, 30, 55, 60), (85, 30, 80, 85),
    (40, 30, 55, 55), (40, 45, 50, 60), (60, 15, 50, 50), (40, 15, 35, 30),
    (75, 45, 80, 90), (75, 45, 80, 75), (60, 45, 60, 55), (70, 15, 65, 65),
    (35, 30, 50, 55), (60, 15, 60, 60), (65, 30, 90, 90), (40, 15, 40, 55),
    (45, 30, 50, 45), (40, 30, 55, 55), (55, 30, 60, 55), (35, 60, 45, 40),
    (45, 30, 75, 70), (35, 30, 60, 35)
]

wb = Workbook()
ws = wb.active
ws.title = "Math Grades"

# Add headers
headers = ["Student ID", "Quiz Average", "Homework Average", "Midterm Exam", "Final Exam"]
ws.append(headers)

# Format headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color="D9D9D9", end_color="D9D9D9", fill_type="solid")
for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal="center")

# Add data
for i, scores in enumerate(uci_data, 1):
    ws.append([f"STU-{i:03d}"] + list(scores))

# Set column widths
ws.column_dimensions['A'].width = 15
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 18
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 15
ws.column_dimensions['F'].width = 18
ws.column_dimensions['G'].width = 15

wb.save("/home/ga/Documents/math_grades.xlsx")
print(f"Created file with {len(uci_data)} student records.")
PYEOF

chown ga:ga "$FILE_PATH"

# Ensure WPS is not currently running
pkill -x et 2>/dev/null || true
pkill -f "/office6/et" 2>/dev/null || true
sleep 2

# Launch WPS Spreadsheet with the file
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et '$FILE_PATH' &"

# Wait for application window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "math_grades"; then
        break
    fi
    sleep 1
done

# Give it a bit more time to fully render
sleep 3

# Maximize and focus
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true

# Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="