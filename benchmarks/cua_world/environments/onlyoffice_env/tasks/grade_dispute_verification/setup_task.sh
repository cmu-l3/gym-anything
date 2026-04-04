#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Grade Dispute Verification Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOC_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw grade data text file
GRADES_FILE="$DOC_DIR/chemistry_grades_raw.txt"

cat > "$GRADES_FILE" << 'EOF'
Chemistry 201 - Spring 2024 Grade Data
Student: [Your Name]
Professor: Dr. Martinez

POSTED FINAL GRADE: 78% (C+)
(You believe this is incorrect based on your records)

Syllabus Grading Breakdown:
- Laboratory Assignments: 30%
- Midterm Exam: 25%
- Final Exam: 30%
- Homework Assignments: 15%

Your Individual Grades:

Labs (10 total, lowest dropped):
Lab 1: 88/100
Lab 2: 92/100
Lab 3: 78/100
Lab 4: 90/100
Lab 5: 85/100
Lab 6: 91/100
Lab 7: 89/100
Lab 8: 87/100
Lab 9: 0/100 (missed - will be dropped)
Lab 10: 93/100

Homework (12 assignments, all count):
HW1: 95, HW2: 90, HW3: 88, HW4: 92, HW5: 87
HW6: 91, HW7: 89, HW8: 94, HW9: 90, HW10: 88
HW11: 92, HW12: 91

Midterm Exam: 82/100

Final Exam: 79/100

TASK: Create a spreadsheet that calculates your actual final grade according to the syllabus formula and identifies the discrepancy with the posted grade.

Expected Calculation:
- Labs: Average the 9 best labs (drop the 0)
- Homework: Average all 12 assignments
- Weighted Final = (Lab_Avg × 0.30) + (Midterm × 0.25) + (Final × 0.30) + (HW_Avg × 0.15)
- Discrepancy = Calculated Grade - Posted Grade (78%)

Save your verification spreadsheet as: /home/ga/Documents/Spreadsheets/grade_verification.xlsx
EOF

chown ga:ga "$GRADES_FILE"

echo "✅ Grade data file created at: $GRADES_FILE"
echo ""
echo "📊 Expected Correct Calculation:"
echo "  - Lab Average (best 9): 88.11%"
echo "  - Homework Average: 90.58%"
echo "  - Midterm: 82%"
echo "  - Final Exam: 79%"
echo "  - Weighted Final: 84.22%"
echo "  - Discrepancy: +6.22 percentage points"
echo ""

# Launch ONLYOFFICE Spreadsheet Editor with a new blank file
SHEET_PATH="$WORKSPACE_DIR/grade_verification.xlsx"

# Create a minimal blank spreadsheet to start with
cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Grade Verification"

# Add a helpful header
ws['A1'] = "Chemistry 201 Grade Verification"
ws['A2'] = "(Refer to chemistry_grades_raw.txt for data)"

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the blank spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_grade_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_grade_task.log || true
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

echo "=== Grade Dispute Verification Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Review the grade data in: /home/ga/Documents/chemistry_grades_raw.txt"
echo "  2. Create a spreadsheet with:"
echo "     - All lab grades (10 labs)"
echo "     - All homework grades (12 assignments)"
echo "     - Exam scores (midterm and final)"
echo "  3. Calculate category averages (remember to drop lowest lab!)"
echo "  4. Calculate weighted final grade using syllabus weights"
echo "  5. Show the discrepancy between calculated and posted grade (78%)"
echo "  6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 Tips:"
echo "  - Use formulas like =AVERAGE(), =SUM(), not manual calculations"
echo "  - Lab 9 scored 0/100 and should be dropped (use best 9 labs)"
echo "  - Weights: Labs 30%, Midterm 25%, Final 30%, Homework 15%"