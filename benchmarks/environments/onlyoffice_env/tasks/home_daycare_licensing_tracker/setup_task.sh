#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Home Daycare Licensing Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with sample data
SHEET_PATH="$WORKSPACE_DIR/daycare_licensing_tracker.xlsx"

cat > /tmp/create_licensing_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Licensing Checklist"

# Add headers with bold formatting
headers = ["Requirement", "Category", "Status", "Documentation Location", "Priority", "Notes", "Due Date"]
for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='center')

# Set column widths for readability
ws.column_dimensions['A'].width = 40
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 30
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 25
ws.column_dimensions['G'].width = 12

# Add 8 initial requirements (pre-filled)
initial_data = [
    ["Fire extinguisher (ABC rated, inspected)", "Safety", "Complete", "Filing cabinet drawer 2", "High", "Receipt dated 3/12", ""],
    ["CPR certification (16 hours)", "Training", "Complete", "Binder - Certifications", "High", "Expires 2026", ""],
    ["Emergency evacuation plan", "Safety", "In Progress", "Computer - Draft folder", "High", "Needs state approval", ""],
    ["Background check (all adults in home)", "Legal", "Not Started", "", "High", "Takes 3-4 weeks", ""],
    ["Business liability insurance ($1M minimum)", "Legal", "Not Started", "", "High", "", ""],
    ["Window guards (all windows below 3rd floor)", "Safety", "Not Started", "", "Medium", "Need installer quote", ""],
    ["Daily schedule posted in each room", "Operations", "Complete", "Printed and laminated", "Low", "", ""],
    ["Parent communication log template", "Operations", "In Progress", "Computer - Draft folder", "Medium", "", ""]
]

for row_idx, row_data in enumerate(initial_data, start=2):
    for col_idx, value in enumerate(row_data, start=1):
        ws.cell(row=row_idx, column=col_idx, value=value)

wb.save(sys.argv[1])
print(f"Licensing tracker spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_licensing_sheet.py
python3 /tmp/create_licensing_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_licensing_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_licensing_task.log || true
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

echo "=== Home Daycare Licensing Tracker Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Maria is preparing for her home daycare licensing inspection in 6 weeks."
echo "  She has 8 requirements tracked so far, but needs to add 7 more."
echo ""
echo "  Your task:"
echo "  1. Add 7 more licensing requirements (at least 1 from each category):"
echo "     - Safety (e.g., outlet covers, stair gates, first aid kit, poison control posted)"
echo "     - Training (e.g., child development course, food handler permit, safe sleep training)"
echo "     - Legal (e.g., business license, tax ID, signed parent contracts)"
echo "     - Facility (e.g., separate nap area, handwashing station, outdoor fence)"
echo "     - Operations (e.g., medication policy, sick child policy, emergency contacts)"
echo ""
echo "  2. Assign status: Complete / In Progress / Not Started"
echo "  3. Set priority: High / Medium / Low"
echo "  4. Add 'Completion %' column (H) with formula: percentage of Complete items"
echo "  5. Apply conditional formatting to Status column:"
echo "     - Complete = Green"
echo "     - In Progress = Yellow"
echo "     - Not Started = Red"
echo "  6. Save (Ctrl+S)"