#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Book Club Voting Sheet Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# The task is to create this file from scratch
# We just launch a blank spreadsheet
SHEET_PATH="$WORKSPACE_DIR/BookClubVote.xlsx"

# Create a truly blank workbook as starting point
cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

# Create a completely blank workbook
wb = Workbook()
ws = wb.active
ws.title = "Sheet1"

# Save the blank workbook
wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the blank spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_bookclub_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_bookclub_task.log || true
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

echo "=== Book Club Voting Sheet Task Setup Complete ==="
echo "📝 Instructions:"
echo ""
echo "Create a voting spreadsheet with the following structure:"
echo ""
echo "Row 1 (Headers - make them BOLD):"
echo "  A1: Book Title"
echo "  B1: Author"
echo "  C1-J1: Member 1, Member 2, ..., Member 8 (8 rating columns)"
echo "  K1: Average Rating"
echo ""
echo "Rows 2-6 (Book Data):"
echo "  Row 2: The Midnight Library | Matt Haig"
echo "  Row 3: Lessons in Chemistry | Bonnie Garmus"
echo "  Row 4: Tomorrow, and Tomorrow, and Tomorrow | Gabrielle Zevin"
echo "  Row 5: The Lincoln Highway | Amor Towles"
echo "  Row 6: Demon Copperhead | Barbara Kingsolver"
echo ""
echo "Column K (Average Formulas):"
echo "  K2: =AVERAGE(C2:J2)"
echo "  K3: =AVERAGE(C3:J3)"
echo "  K4: =AVERAGE(C4:J4)"
echo "  K5: =AVERAGE(C5:J5)"
echo "  K6: =AVERAGE(C6:J6)"
echo ""
echo "Save the file as BookClubVote.xlsx (Ctrl+S)"
echo ""
echo "Note: Leave member rating cells (C2:J6) empty - members will fill them later"