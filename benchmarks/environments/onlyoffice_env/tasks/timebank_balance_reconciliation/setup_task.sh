#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Time Bank Balance Reconciliation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
SPREADSHEET_DIR="/home/ga/Documents/Spreadsheets"
DESKTOP_DIR="/home/ga/Desktop"
sudo -u ga mkdir -p "$SPREADSHEET_DIR"
sudo -u ga mkdir -p "$DESKTOP_DIR"

# Create the template spreadsheet with headers only
TEMPLATE_PATH="$SPREADSHEET_DIR/timebank_template.xlsx"

cat > /tmp/create_timebank_template.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Sarah Chen"

# Add headers
headers = ["Date", "Service Type", "Hours Earned", "Hours Spent", "Balance"]
ws.append(headers)

# Bold and center headers
for idx, cell in enumerate(ws[1], start=1):
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='center')

# Set column widths for readability
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 20
ws.column_dimensions['C'].width = 14
ws.column_dimensions['D'].width = 14
ws.column_dimensions['E'].width = 12

wb.save(sys.argv[1])
print(f"Template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_timebank_template.py
python3 /tmp/create_timebank_template.py "$TEMPLATE_PATH"
chown ga:ga "$TEMPLATE_PATH"

echo "✅ Template created at: $TEMPLATE_PATH"

# Create the notes file with transaction data
NOTES_PATH="$DESKTOP_DIR/sarah_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
═══════════════════════════════════════════════════════════
    OAKMONT COMMUNITY TIME BANK
    Transaction Notes for Sarah Chen
═══════════════════════════════════════════════════════════

From coordinator's notebook (March-April 2024):

📝 3/15/24 - Sarah did pet sitting for the Johnsons
   Total hours EARNED: 3.5 hrs

📝 3/22/24 - Sarah got help with spring garden prep
   Total hours SPENT: 2.0 hrs

📝 4/5/24 - Sarah tutored math (high school student)
   Total hours EARNED: 4.0 hrs

📝 4/18/24 - Sarah had home repair done (fixing deck)
   Total hours SPENT: 5.5 hrs

📝 4/30/24 - Sarah made freezer meals for new parent
   Total hours EARNED: 2.5 hrs

═══════════════════════════════════════════════════════════
INSTRUCTIONS:
1. Enter these transactions into the spreadsheet template
2. Create formulas to calculate running balance
3. Apply conditional formatting to highlight negative balances
4. Save as: sarah_chen_timebank.xlsx

NOTE: Sarah wants to request house cleaning (3 hrs).
      Calculate if she has enough hours available!
═══════════════════════════════════════════════════════════
EOF

chown ga:ga "$NOTES_PATH"

echo "✅ Notes file created at: $NOTES_PATH"

# Launch ONLYOFFICE with the template
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$TEMPLATE_PATH' > /tmp/onlyoffice_timebank_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_timebank_task.log || true
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

# Open notes file in text editor for reference (gedit or xed)
echo "Opening notes file for reference..."
su - ga -c "DISPLAY=:1 xdg-open '$NOTES_PATH' > /tmp/notes_viewer.log 2>&1 &" || true
sleep 2

# Arrange windows side by side if possible (optional, best effort)
su - ga -c "DISPLAY=:1 wmctrl -r 'sarah_notes.txt' -e 0,0,0,640,1080" 2>/dev/null || true
su - ga -c "DISPLAY=:1 wmctrl -r 'ONLYOFFICE' -e 0,640,0,1280,1080" 2>/dev/null || true

echo "=== Time Bank Balance Reconciliation Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. Enter transaction data from the notes file into the spreadsheet"
echo "  2. Create running balance formulas in column E"
echo "     - First row (E2): =C2-D2"
echo "     - Subsequent rows: =E2+C3-D3 (and so on)"
echo "  3. Apply conditional formatting to balance column (E2:E6)"
echo "     - Rule: If cell value < 0, apply red/pink background"
echo "  4. Format for professionalism:"
echo "     - Headers should be bold"
echo "     - Hours should show one decimal place"
echo "  5. Save as: /home/ga/Documents/Spreadsheets/sarah_chen_timebank.xlsx"
echo ""
echo "Expected final balance: 2.5 hours"
echo "(3.5 + 4.0 + 2.5 - 2.0 - 5.5 = 2.5)"