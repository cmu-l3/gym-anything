#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Karaoke Queue Manager Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create party scenario file
SCENARIO_PATH="/home/ga/Documents/party_scenario.txt"

cat > "$SCENARIO_PATH" << 'SCENARIO_EOF'
BIRTHDAY KARAOKE PARTY - SONG REQUESTS
=======================================

Birthday Person: Alex (PRIORITY - gets 2 songs early in the queue!)

Song Requests (received via text throughout the evening):

1. Jordan - "Bohemian Rhapsody" (6 min)
2. Sam - "Valerie" (4 min)
3. Taylor - "Rolling in the Deep" (4 min)
4. Alex - "Don't Stop Believin'" (4 min) [BIRTHDAY PERSON]
5. Morgan - "Uptown Funk" (5 min)
6. Jordan - "Somebody to Love" (5 min) [2nd request from Jordan]
7. Casey - "Shallow" (4 min)
8. Alex - "Livin' on a Prayer" (4 min) [BIRTHDAY PERSON - 2nd song]
9. River - "I Wanna Dance with Somebody" (5 min)
10. Sam - "Titanium" (4 min) [2nd request from Sam]
11. Avery - "Mr. Brightside" (4 min)
12. Taylor - "Shake It Off" (4 min) [2nd request from Taylor]
13. Drew - "Sweet Caroline" (3 min)
14. Morgan - "Can't Stop the Feeling" (4 min) [2nd request from Morgan]

=======================================
YOUR TASK:
1. Organize this into a FAIR queue where:
   - Alex's songs get priority (both in top 4 positions)
   - People who haven't sung yet go BEFORE people requesting 2nd songs
   - Track status (Waiting/Performing/Completed or similar)
   - Calculate running time so you can answer "when's my turn?"
   
2. VENUE CONSTRAINT: Closes in 90 minutes!

3. FAIRNESS RULES:
   - First-time singers before repeat singers
   - Birthday person gets special treatment (early placement)
   - Clear status tracking so you can mark songs as they complete
   
4. Your spreadsheet should be easy to scan and update in real-time!

People keep asking "when's my turn?" - help them out!
SCENARIO_EOF

chown ga:ga "$SCENARIO_PATH"
echo "✅ Party scenario created at: $SCENARIO_PATH"

# Create the initial spreadsheet (mostly blank, ready for organization)
SHEET_PATH="$WORKSPACE_DIR/karaoke_queue.xlsx"

cat > /tmp/create_karaoke_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Karaoke Queue"

# Add instructions at top
ws['A1'] = "BIRTHDAY KARAOKE PARTY QUEUE"
ws['A1'].font = Font(bold=True, size=14)
ws['A2'] = "Organize the song requests from party_scenario.txt into a fair queue system"
ws['A3'] = "Remember: Alex (birthday person) gets priority! Fair rotation for repeats!"
ws['A4'] = ""

# Add suggested column headers (row 5)
ws['A5'] = "Queue #"
ws['B5'] = "Singer Name"
ws['C5'] = "Song Title"
ws['D5'] = "Length (min)"
ws['E5'] = "Status"
ws['F5'] = "Running Time"

# Format headers
header_font = Font(bold=True, size=11)
header_fill = PatternFill(start_color="DDDDDD", end_color="DDDDDD", fill_type="solid")
for col in ['A5', 'B5', 'C5', 'D5', 'E5', 'F5']:
    ws[col].font = header_font
    ws[col].fill = header_fill
    ws[col].alignment = Alignment(horizontal='center')

# Adjust column widths
ws.column_dimensions['A'].width = 10
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 30
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 15

# Add a reminder note
ws['A25'] = "VENUE CLOSES IN 90 MINUTES - PLAN ACCORDINGLY!"
ws['A25'].font = Font(bold=True, color="FF0000")

wb.save(sys.argv[1])
print(f"Karaoke spreadsheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_karaoke_sheet.py
python3 /tmp/create_karaoke_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Karaoke queue spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_karaoke_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_karaoke_task.log || true
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

echo "=== Karaoke Queue Manager Task Setup Complete ==="
echo ""
echo "🎤 PARTY SCENARIO:"
echo "  - Birthday person: Alex (needs 2 songs with PRIORITY)"
echo "  - Total requests: 14 songs from 8 different people"
echo "  - Several people want to sing twice"
echo "  - Venue closes in 90 minutes"
echo ""
echo "📋 YOUR TASK:"
echo "  1. Read the party scenario: /home/ga/Documents/party_scenario.txt"
echo "  2. Organize all song requests into the spreadsheet"
echo "  3. Put Alex's 2 songs in top 4 positions (birthday priority!)"
echo "  4. Implement fair rotation (first-timers before repeats)"
echo "  5. Add status tracking (Waiting/Performing/Completed)"
echo "  6. Calculate running times (formulas for cumulative time)"
echo "  7. Save when done (Ctrl+S)"
echo ""
echo "💡 TIP: People keep asking 'when's my turn?' - your queue should answer that!"