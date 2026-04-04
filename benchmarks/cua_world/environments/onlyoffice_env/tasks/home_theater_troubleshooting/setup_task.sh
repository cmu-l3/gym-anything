#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Home Theater Troubleshooting Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
DOCS_DIR="/home/ga/Documents"
SHEETS_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$DOCS_DIR"
sudo -u ga mkdir -p "$SHEETS_DIR"

# Create the messy troubleshooting notes file
NOTES_PATH="$DOCS_DIR/theater_notes.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
Home Theater Troubleshooting Notes
===================================

march 15 - sound cut out again during movie on PS5. tried different HDMI cable (the new one from amazon). seemed to work but happened again 2 days later. frustrating!

3/17 - rear left speaker not connecting. power cycled receiver. worked immediately.

mar 18 - HDMI handshake issue with roku, blank screen for like 10 sec when switching input. updated receiver firmware to latest version. still testing if fixed.

3/20 - audio cutout during netflix on roku too! not just PS5. switched to different HDMI port on receiver (port 3 instead of port 1). no cutout for 2 hours tonight.

March 22 - lip sync delay on blu-ray player. adjusted audio delay setting to +150ms in receiver menu. fixed for that movie at least.

3/23 - rear speaker dropout again (same left speaker). checked wireless connection strength indicator. moved receiver antenna position. seems stable now for last 3 hrs.

mar 24 - audio cutout came back even after HDMI port change yesterday. getting really frustrated. maybe receiver is actually defective?

3/25 - tried optical audio instead of HDMI ARC for roku. no cutouts for 3 days straight! might be ARC issue not receiver itself.

march 27 - switched PS5 to optical audio cable too. testing this configuration.

3/28 - lip sync delay on PS5 now with optical connection. adjusted receiver audio delay to +100ms. seems ok so far.

march 29 - rear speakers both working great for a week now. antenna repositioning must have fixed it.

3/30 - audio cutout on PS5 with optical! so it's not just HDMI. might be receiver overheating? added small fan.

April 1 - no issues for 2 days with fan running. might have been thermal problem.

4/2 - HDMI handshake on Roku still occasional. takes 5-10 sec but does work eventually. can live with it.

4/3 - audio cutout again on PS5 during intense game scene. checked receiver temp - very hot. fan helping but not enough.

apr 5 - contacted manufacturer support. they suggested factory reset. backed up settings and did reset. testing now.

4/6 - no audio cutouts since factory reset! been testing heavily for 2 days. lip sync still needs +100ms adjustment but stable.

april 7 - rear speakers dropped once today. power cycled. back to normal. might need to replace wireless transmitter eventually.

4/8 - everything working well. HDMI handshake improved after factory reset too. only takes 2-3 sec now instead of 10.

4/9 - audio cutout returned during movie on blu-ray player. this is definitely a receiver hardware issue. planning to RMA.
NOTESEOF

chown ga:ga "$NOTES_PATH"

echo "✅ Troubleshooting notes created at: $NOTES_PATH"

# Display the notes file for the user to reference
echo ""
echo "📄 Notes file preview (first 20 lines):"
head -n 20 "$NOTES_PATH"
echo ""
echo "[... see full file at $NOTES_PATH ...]"
echo ""

# Launch gedit or a text editor with the notes file for easy reference
echo "Opening notes file in text editor for reference..."
su - ga -c "DISPLAY=:1 gedit '$NOTES_PATH' > /tmp/gedit_notes.log 2>&1 &" || true
sleep 2

# Position the text editor window to the side
su - ga -c "DISPLAY=:1 wmctrl -r 'gedit' -e 0,10,10,600,800" 2>/dev/null || true

# Launch ONLYOFFICE Spreadsheet Editor (empty, user will create new file)
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:spreadsheet > /tmp/onlyoffice_sheet_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_sheet_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Position ONLYOFFICE window to the right side
sleep 2
su - ga -c "DISPLAY=:1 wmctrl -r 'ONLYOFFICE' -e 0,620,10,700,900" 2>/dev/null || true

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 800 500 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Home Theater Troubleshooting Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "=========================================="
echo "You have messy troubleshooting notes in: $NOTES_PATH"
echo ""
echo "CREATE A SPREADSHEET WITH:"
echo "1. Column headers:"
echo "   - Date (format: MM/DD/YYYY)"
echo "   - Equipment/Source (e.g., PS5, Roku, Receiver, Rear Speakers)"
echo "   - Symptom (problem description)"
echo "   - Action Taken (what you tried)"
echo "   - Result (outcome - did it work? recur?)"
echo ""
echo "2. Extract AT LEAST 8 troubleshooting incidents from notes"
echo ""
echo "3. Add a COUNTIF formula somewhere to count how many times"
echo "   'Audio Cutout' appears as a symptom"
echo ""
echo "4. Apply CONDITIONAL FORMATTING to highlight rows where"
echo "   Result contains 'Failed' or 'Recurred' (use red/pink)"
echo ""
echo "5. Sort the table chronologically (earliest to latest)"
echo ""
echo "6. Save as: /home/ga/Documents/Spreadsheets/theater_troubleshooting.xlsx"
echo ""
echo "=========================================="