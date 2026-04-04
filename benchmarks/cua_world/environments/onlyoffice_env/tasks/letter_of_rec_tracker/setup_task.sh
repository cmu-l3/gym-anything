#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Letter of Rec Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a minimal blank spreadsheet as starting point
SHEET_PATH="$WORKSPACE_DIR/lor_tracker.xlsx"

cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "LoR Tracker"

# Start with completely blank sheet - user will create structure
# Just save empty workbook
wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the blank spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_lor_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_lor_task.log || true
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

echo "=== Letter of Rec Tracker Task Setup Complete ==="
echo ""
echo "📝 Task: Create a letter of recommendation tracking spreadsheet"
echo ""
echo "Instructions:"
echo "  1. Create header row with columns:"
echo "     - Program Name"
echo "     - Deadline"
echo "     - Recommender 1, 2, 3 (or similar)"
echo "     - Materials Sent / Status / Notes"
echo ""
echo "  2. Add at least 6 graduate programs with data:"
echo "     - Program names (e.g., MIT Brain Sciences, Stanford Neuroscience)"
echo "     - Deadlines (e.g., Dec 1, Dec 15, Jan 5)"
echo "     - Recommender names (e.g., Dr. Chen, Dr. Park, Dr. Rodriguez)"
echo "     - Status info (e.g., 'All submitted', 'Waiting on Chen')"
echo ""
echo "  3. Format headers (bold recommended)"
echo ""
echo "  4. Save the spreadsheet (Ctrl+S) as lor_tracker.xlsx"
echo ""
echo "Example structure:"
echo "  | Program Name | Deadline | Rec 1 | Rec 2 | Rec 3 | Status |"
echo "  | MIT Brain... | Dec 1    | Chen  | Park  | Rodriguez | 2/3 submitted |"