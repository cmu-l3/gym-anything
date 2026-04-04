#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Birding Log Compilation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
NOTES_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$NOTES_DIR"

# Create field notes text file with realistic birding observations
FIELD_NOTES="$NOTES_DIR/field_notes_march2024.txt"

cat > "$FIELD_NOTES" << 'NOTES_EOF'
FIELD NOTES - RIVERSIDE PARK TRAIL - MARCH 2024
================================================

March 10, 2024 - Morning (~7:30 AM)
- American Robin - saw 3 individuals feeding on lawn near parking lot
- Northern Cardinal - 1 male, bright red, singing from oak tree
- Song Sparrow - heard only, didn't see it

March 12, 2024 - Riverside Park Trail
(forgot to note exact time, was afternoon-ish)
- Red-tailed Hawk?? - saw 1 soaring, pretty far away, could have been Red-shouldered Hawk, wasn't sure
- American Goldfinch - small flock, approximately 5 or 6 birds, feeding on seeds
- Black-capped Chickadee - 2 at the feeder station

March 14, 2024 - 8:15 AM - Riverside Park Trail  
- White-breasted Nuthatch - 1 on tree trunk
- Tufted Titmouse - 1, very vocal

March 15, 2024 - Early morning - Riverside Park Trail
- Downy Woodpecker - 1 male on dead snag
- Northern Cardinal - 1 female, might be same territory as March 10?
- Blue Jay - 2, very noisy

NOTES:
- Need to confirm hawk ID on March 12 - too distant to be certain
- Goldfinch count was approximate, they kept moving
- Some times are missing because I forgot to check my watch
NOTES_EOF

chown ga:ga "$FIELD_NOTES"

echo "✅ Field notes created at: $FIELD_NOTES"

# Display field notes in a text editor for easy reference
echo "Opening field notes in text editor for reference..."
su - ga -c "DISPLAY=:1 xdg-open '$FIELD_NOTES' > /tmp/xdg_open.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 gedit '$FIELD_NOTES' > /tmp/gedit.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 mousepad '$FIELD_NOTES' > /tmp/mousepad.log 2>&1 &" || \
echo "Could not open text editor, agent will need to open notes manually"

sleep 2

# Launch ONLYOFFICE Calc with blank spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new spreadsheet > /tmp/onlyoffice_birding_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "WARNING: ONLYOFFICE may not have started"
    cat /tmp/onlyoffice_birding_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "WARNING: ONLYOFFICE window did not appear quickly"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Birding Log Compilation Task Setup Complete ==="
echo ""
echo "📋 Field notes have been created at:"
echo "   $FIELD_NOTES"
echo ""
echo "📝 Your task:"
echo "  1. Review the field notes (opened in text editor)"
echo "  2. In ONLYOFFICE Calc, create a structured spreadsheet with columns:"
echo "     - Date"
echo "     - Time (or leave blank if unknown)"
echo "     - Location" 
echo "     - Species"
echo "     - Count"
echo "     - Notes / ID Confidence"
echo "  3. Enter all observations from the field notes (at least 5 species)"
echo "  4. Handle uncertain IDs appropriately (use '?', 'Hawk sp.', or notes)"
echo "  5. Handle missing data appropriately (leave blank or mark as unknown)"
echo "  6. Save with meaningful filename like 'Birding_Log_March2024.xlsx'"
echo "     to /home/ga/Documents/Spreadsheets/"
echo ""
echo "Expected observations:"
echo "  - March 10: Robin (3), Cardinal (1 male), Song Sparrow"
echo "  - March 12: Hawk sp.? (1, uncertain), Goldfinch (~5-6), Chickadee (2)"
echo "  - March 14: Nuthatch (1), Titmouse (1)"
echo "  - March 15: Woodpecker (1), Cardinal (1 female), Blue Jay (2)"