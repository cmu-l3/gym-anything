#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Symptom Diary Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet that the user will configure
SHEET_PATH="$WORKSPACE_DIR/symptom_diary.xlsx"

cat > /tmp/create_symptom_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
import sys

wb = Workbook()
ws = wb.active
ws.title = "Symptom Tracker"

# The user needs to create the structure themselves
# We'll just provide a completely blank sheet to make it more realistic
# Or we could provide minimal guidance text

# Add a single instruction cell that user should delete/replace
ws['A1'] = "Create symptom tracking headers here"
ws['A1'].font = Font(italic=True, color="808080")

# Make sheet more realistic by setting some default column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 10
ws.column_dimensions['C'].width = 18
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 18
ws.column_dimensions['F'].width = 20
ws.column_dimensions['G'].width = 18
ws.column_dimensions['H'].width = 25

wb.save(sys.argv[1])
print(f"Blank symptom diary spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_symptom_sheet.py
python3 /tmp/create_symptom_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_symptom_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_symptom_task.log || true
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

echo "=== Symptom Diary Tracker Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "SCENARIO: You need to create a symptom tracking spreadsheet for"
echo "a doctor's appointment. Track recurring health symptoms with"
echo "organized data and visual indicators."
echo ""
echo "REQUIRED STEPS:"
echo ""
echo "1. CREATE COLUMN HEADERS (Row 1):"
echo "   - Column A: Date"
echo "   - Column B: Time"
echo "   - Column C: Symptom Type"
echo "   - Column D: Severity (1-10)"
echo "   - Column E: Duration (minutes)"
echo "   - Column F: Potential Trigger"
echo "   - Column G: Medication Taken"
echo "   - Column H: Notes"
echo ""
echo "2. FORMAT HEADERS:"
echo "   - Make header text BOLD"
echo "   - Apply background color (light blue, gray, or any color)"
echo "   - Center-align header text"
echo "   - Apply borders to header cells"
echo ""
echo "3. SET UP DATA VALIDATION:"
echo "   - Select cells D2:D100 (Severity column)"
echo "   - Apply data validation: restrict to numbers 1-10"
echo "   - (Data menu > Data Validation or Validity)"
echo ""
echo "4. APPLY CONDITIONAL FORMATTING:"
echo "   - Select cells D2:D100 (Severity column)"
echo "   - Set up conditional formatting rules:"
echo "     * Values 1-3: Green background"
echo "     * Values 4-7: Yellow or Orange background"
echo "     * Values 8-10: Red or Pink background"
echo ""
echo "5. ENTER SAMPLE DATA (at least 5 entries):"
echo "   Example entries:"
echo "   - 2024-01-15 | 14:30 | Headache | 7 | 120 | Bright screen | Ibuprofen | After meeting"
echo "   - 2024-01-16 | 09:00 | Nausea | 5 | 45 | Skipped breakfast | None | Better after eating"
echo "   - Add at least 3 more realistic entries..."
echo ""
echo "6. CREATE SUMMARY SECTION (starting at row 102):"
echo "   - Cell A102: 'SUMMARY STATISTICS' (bold, larger font)"
echo "   - Cell A103: 'Total Symptom Episodes:'"
echo "   - Cell B103: =COUNTA(C2:C100)"
echo "   - Cell A104: 'Average Severity:'"
echo "   - Cell B104: =AVERAGE(D2:D100)"
echo "   - Cell A105: 'Highest Severity:'"
echo "   - Cell B105: =MAX(D2:D100)"
echo ""
echo "7. FORMAT DATE COLUMN:"
echo "   - Format column A as proper dates (MM/DD/YYYY)"
echo ""
echo "8. ADJUST COLUMN WIDTHS:"
echo "   - Make all content fully visible and professional"
echo ""
echo "9. SAVE THE SPREADSHEET (Ctrl+S)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"