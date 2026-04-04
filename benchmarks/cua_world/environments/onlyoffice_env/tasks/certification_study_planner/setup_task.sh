#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Certification Study Planner Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet for the study planner
SHEET_PATH="$WORKSPACE_DIR/study_schedule.xlsx"

cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Study Plan"

# Create completely blank spreadsheet for agent to work with
# Agent will create the entire study schedule from scratch

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_study_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_study_task.log || true
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

echo "=== Certification Study Planner Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Create a certification study planner with:"
echo "  1. Header section (Rows 1-3):"
echo "     - A1: Title (e.g., 'PMP Certification Study Schedule')"
echo "     - A2: 'Exam Date:', B2: =TODAY()+56"
echo "     - A3: 'Days Remaining:', B3: =B2-TODAY()"
echo "  2. Study plan table (Row 5+):"
echo "     - Headers: Week | Knowledge Area | Study Hours | Practice Questions | Completed | Priority"
echo "     - Add 8 weeks of study data"
echo "  3. Summary section (Rows 15+):"
echo "     - Total Study Hours: =SUM(C6:C13)"
echo "     - Total Practice Questions: =SUM(D6:D13)"
echo "     - Weeks Completed: =COUNTIF(E6:E13,TRUE)"
echo "     - Completion Percentage: =B17/8*100"
echo "  4. Save (Ctrl+S)"