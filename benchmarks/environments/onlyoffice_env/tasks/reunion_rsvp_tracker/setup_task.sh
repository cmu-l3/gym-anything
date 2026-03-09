#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Reunion RSVP Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a starter spreadsheet with column headers as hints
SHEET_PATH="$WORKSPACE_DIR/reunion_tracker.xlsx"

cat > /tmp/create_reunion_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Reunion RSVPs"

# Add column headers as guidance
headers = ["Last Name", "First Name", "Email", "Phone", "RSVP Status", "Bringing Guest?", "Meal Choice", "Notes"]

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx)
    cell.value = header
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='left')

# Set column widths for better visibility
ws.column_dimensions['A'].width = 15
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 25
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 15
ws.column_dimensions['F'].width = 18
ws.column_dimensions['G'].width = 15
ws.column_dimensions['H'].width = 25

# Add instruction row (will be deleted or overwritten by agent)
ws['A2'] = "[Enter classmate data below]"

wb.save(sys.argv[1])
print(f"Reunion tracker spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_reunion_sheet.py
python3 /tmp/create_reunion_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Reunion tracker spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_reunion_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_reunion_task.log || true
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

echo "=== Reunion RSVP Tracker Task Setup Complete ==="
echo ""
echo "📋 TASK: Create a reunion RSVP tracker spreadsheet"
echo ""
echo "📝 Instructions:"
echo "  1. The column headers are already provided as guidance"
echo "  2. Enter data for the following 8 classmates:"
echo ""
echo "     Last Name  | First Name | Email              | Phone      | RSVP    | Guest? | Meal       | Notes"
echo "     -----------|------------|--------------------|-----------:|---------|--------|------------|---------------------------"
echo "     Chen       | Michael    | mchen@email.com    | 555-0101   | Yes     | No     | Vegetarian | Replied via email"
echo "     Rodriguez  | Sarah      | sarah.r@email.com  | 555-0102   | Yes     | Yes    | Chicken    | +1 is spouse"
echo "     Johnson    | Taylor     | -                  | 555-0103   | Maybe   | No     | -          | Waiting on work schedule"
echo "     Williams   | Jordan     | jwill@email.com    | -          | Yes     | No     | Beef       | Asked about parking"
echo "     Patel      | Priya      | priya.patel@...    | 555-0105   | No      | No     | -          | Traveling that weekend"
echo "     Thompson   | Alex       | -                  | -          | Yes     | Yes    | Vegetarian | Both vegetarian meals"
echo "     Martinez   | Chris      | c.martinez@...     | 555-0107   | Yes     | No     | Chicken    | Early bird discount paid"
echo "     Anderson   | Blake      | blake.a@email.com  | 555-0108   | Yes     | Yes    | Beef       | Requested table near band"
echo ""
echo "  3. After the data, add a blank row, then create a SUMMARY section with:"
echo "     - Label: 'Total Confirmed' → Formula: count of 'Yes' in RSVP Status (should be 6)"
echo "     - Label: 'Total with Guests' → Formula: count of 'Yes' in Bringing Guest column (should be 3)"
echo "     - Label: 'Total Headcount' → Formula: Confirmed + Guests (should be 9)"
echo "     - Label: 'Vegetarian Meals' → Formula: count of 'Vegetarian' in Meal Choice (should be 3)"
echo "     - Label: 'Chicken Meals' → Formula: count of 'Chicken' (should be 2)"
echo "     - Label: 'Beef Meals' → Formula: count of 'Beef' (should be 3)"
echo "     - Label: 'Cost per Person' → Value: 45 (no formula needed)"
echo "     - Label: 'Expected Revenue' → Formula: Total Headcount × Cost per Person (should be $405)"
echo ""
echo "  4. Formatting:"
echo "     - Column headers should be BOLD (already done, but verify)"
echo "     - Apply CURRENCY formatting to 'Cost per Person' and 'Expected Revenue'"
echo ""
echo "  5. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected results:"
echo "  - Total Confirmed: 6"
echo "  - Total Headcount: 9 (6 confirmed + 3 guests)"
echo "  - Vegetarian Meals: 3"
echo "  - Chicken Meals: 2"
echo "  - Beef Meals: 3"
echo "  - Expected Revenue: $405"