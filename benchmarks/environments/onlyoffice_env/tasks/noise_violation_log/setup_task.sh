#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Noise Violation Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw incident notes file with realistic, messy data
RAW_NOTES_PATH="$WORKSPACE_DIR/noise_incidents_raw.txt"

cat > "$RAW_NOTES_PATH" << 'EOF'
NOISE INCIDENT NOTES - APARTMENT 3B (Me) vs 4B (Upstairs Neighbor)

11/3/2024 - Woke up to LOUD music around 2:30 AM. Bass was shaking my ceiling. Went on until almost 4 AM. I banged on the ceiling at 3:15 but no response. Too exhausted to go upstairs.

Nov 10 - Friday night party AGAIN. Started hearing voices, laughing, and bass around 11:45 PM. Music lasted past 1:30 AM. Finally fell asleep with earplugs around 2 AM. Didn't complain because too tired.

11/17/2024 Sunday - Construction sounds or moving furniture?? Heavy dragging and banging starting at 7:15 AM ON A SUNDAY MORNING. Lasted about an hour and 15 minutes. Called management - they said they'd "look into it".

Nov 22 - Wednesday - Late night movie or TV? Very loud volume, could hear dialogue through ceiling. Started around 11:20 PM, went until about 12:45 AM. Knocked on ceiling, volume went down for 10 min then back up.

Thanksgiving 11/23 - Big party Thursday night. Lots of people, music, stomping. Started maybe 10 PM? Went until at least 2:30 AM. Holiday so I guess they thought it was okay. It wasn't.

Dec 1 2024 - Saturday night party. Music started around 10:30 PM, went until 1:45 AM. Heavy bass, could feel it in my chest. No response to ceiling knocks.

12/8 - Sunday morning power tools!!! Drilling or sawing starting 8 AM. On a Sunday!! Lasted 45 minutes. Management voicemail left but no callback yet.

Dec 14 - Friday party from about 11 PM to 2:15 AM. Same loud music pattern. Starting to document everything now because this is ridiculous.

Dec 19 2024 - Thursday night - Sounded like furniture moving and rearranging late at night. Started around 11:40 PM and went for almost 2 hours until 1:30 AM. Who rearranges furniture at midnight?!

12/21 - Saturday - Another party. 10:15 PM start, didn't end until 3 AM. WORST ONE YET. Considered calling police but decided to document instead.

Christmas Day 12/25 - Holiday party. Loud music and voices from 9 PM until 1:30 AM. I get it's Christmas but some of us have work the next day.

Dec 28 - Saturday night music again. 10:45 PM to 2 AM. Same pattern every weekend now.

Jan 2 2025 - Thursday - New Year's hangover party? Loud music starting around 10 PM, went past midnight (12:45 AM when I finally fell asleep).

1/5/25 Sunday - More construction!! Power saw or drill at 7:45 AM on Sunday. About 1.5 hours. Left another message with management.

Jan 11 - Saturday late night party. Started 11 PM, still going when I left for early morning appointment at 2:30 AM (so at least 3.5 hours).

1/16/2025 - Thursday evening - Not late night but SUPER LOUD music from 8:30 PM to 10:15 PM. During normal hours but unreasonably loud.

Jan 18 - Saturday - Party from 10:30 PM to 1:15 AM. Vibrating bass, multiple voices.

Last Saturday 1/25 - Another weekend party. 11 PM to 2:45 AM. Taking photos of my decibel meter readings now (peaked at 68 dB in MY apartment).

EOF

chown ga:ga "$RAW_NOTES_PATH"
echo "✅ Raw incident notes created at: $RAW_NOTES_PATH"

# Create initial empty spreadsheet
SHEET_PATH="$WORKSPACE_DIR/Noise_Violation_Log.xlsx"

cat > /tmp/create_noise_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Noise Log"

# Create a blank spreadsheet - the agent needs to add everything
# Just to ensure the file exists and can be opened

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_noise_sheet.py
python3 /tmp/create_noise_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_noise_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_noise_task.log || true
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

echo "=== Noise Violation Log Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review raw notes at: $RAW_NOTES_PATH"
echo "  2. Create structured table with columns:"
echo "     - Date | Day of Week | Start Time | End Time | Duration (hrs)"
echo "     - Violation Type | During Quiet Hours? | Description | Action Taken"
echo "  3. Extract and organize incident data from raw notes"
echo "  4. Use formulas to calculate durations"
echo "  5. Add summary statistics section"
echo "  6. Sort chronologically by date"
echo "  7. Apply professional formatting (borders, bold headers)"
echo "  8. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Building Quiet Hours:"
echo "  - Weekdays: 10:00 PM - 8:00 AM"
echo "  - Weekends: 11:00 PM - 9:00 AM"