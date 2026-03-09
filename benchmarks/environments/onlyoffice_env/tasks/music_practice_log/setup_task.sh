#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Music Practice Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet
SHEET_PATH="$WORKSPACE_DIR/practice_log.xlsx"

cat > /tmp/create_practice_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

# Create a completely blank workbook
wb = Workbook()
ws = wb.active
ws.title = "Sheet1"

# Save blank workbook - agent must create everything
wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_practice_sheet.py
python3 /tmp/create_practice_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_practice_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_practice_task.log || true
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

echo "=== Music Practice Log Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Create a piano practice log with the following structure:"
echo ""
echo "  Row 1 - Headers:"
echo "    A1: Date"
echo "    B1: Duration (min)"
echo "    C1: Pieces Worked On"
echo "    D1: Technique Focus"
echo "    E1: Tempo (bpm)"
echo "    F1: Notes"
echo ""
echo "  Rows 2-6 - Practice Sessions:"
echo "    Session 1: 2025-01-13, 45 min, Chopin Waltz Op. 64 No. 2, Scales - A minor, 120, Left hand still shaky"
echo "    Session 2: 2025-01-14, 60 min, Hanon Exercise No. 1, Finger independence, 80, Felt good, increased tempo"
echo "    Session 3: 2025-01-15, 30 min, Chopin Waltz, Right hand alone, 100, Worked on measures 16-24"
echo "    Session 4: 2025-01-16, 15 min, Sight-reading exercises, Reading treble clef, (leave empty), Only had 15 min before school"
echo "    Session 5: 2025-01-17, 90 min, Chopin Waltz, Bach Prelude, Hands together, dynamics, 108, Big breakthrough on the tricky section!"
echo ""
echo "  Row 8 - Total:"
echo "    A8: Total Minutes This Week:"
echo "    B8: =SUM(B2:B6)  [MUST use a formula]"
echo ""
echo "  Expected total: 240 minutes"
echo "  Save the spreadsheet (Ctrl+S)"