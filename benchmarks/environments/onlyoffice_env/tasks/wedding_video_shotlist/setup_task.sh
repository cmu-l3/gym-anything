#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Wedding Video Shot List Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
DESKTOP_DIR="/home/ga/Desktop"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DESKTOP_DIR"

# Create the raw shooting notes file on Desktop
RAW_NOTES_PATH="$DESKTOP_DIR/shot_notes_raw.txt"

cat > "$RAW_NOTES_PATH" << 'EOF'
MARTINEZ-CHEN WEDDING SHOOTING NOTES
=====================================
(Unorganized - needs cleanup before Saturday!)

Raw shot ideas from client meetings & venue walkthrough:

- bride getting ready with bridesmaids (hair/makeup)
- ceremony entrance IMPORTANT - bride's father walking her down aisle
- ring exchange closeup - get both hands
- first kiss MUST GET - multiple angles if possible
- family photos: bride's parents, groom's parents, both sets of siblings
- couple at the fountain (golden hour lighting if we can time it)
- reception entrance - DJ will announce them
- first dance CRITICAL - this is their song, don't miss it
- cake cutting - traditional moment
- speeches: best man (groom's brother), maid of honor (bride's sister)
- detail shots throughout day: rings, dress detail, bouquet, flowers, venue sign
- candid guest moments during cocktail hour
- couple portraits in the garden area - lots of greenery
- getting ready: groom with groomsmen (getting dressed, ties)
- ceremony full wide shot - capture whole venue and guests
- vows exchange IMPORTANT - audio is critical here
- bouquet toss - if they decide to do it
- venue establishing shots - exterior and interior

VENUE INFO:
- Location: Rosewood Gardens, 123 Oak Street
- Ceremony: 2:00 PM in outdoor pavilion
- Cocktail hour: 3:00-4:30 PM
- Reception: 5:00-10:00 PM in main hall
- Golden hour: approximately 6:30 PM in March

EQUIPMENT NOTES:
- Bring backup batteries for ceremony (no power outside)
- Second shooter: Maria (brief her on critical shots)
- Drone approved for exterior shots before 4 PM

CLIENT PRIORITIES:
- Father-daughter moment (entrance) is very emotional for them
- First dance - couple has been practicing for months
- Vows - they wrote custom vows, capture audio clearly
EOF

chown ga:ga "$RAW_NOTES_PATH"
echo "✅ Raw notes created at: $RAW_NOTES_PATH"

# Create the initial blank document for the shot list
DOC_PATH="$WORKSPACE_DIR/Martinez_Wedding_ShotList.docx"

cat > /tmp/create_shotlist_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Just create a completely blank document
# The agent needs to add everything

doc.save(sys.argv[1])
print(f"Blank shot list document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_shotlist_doc.py
python3 /tmp/create_shotlist_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Blank shot list document created at: $DOC_PATH"

# Launch ONLYOFFICE Document Editor with the shot list document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_shotlist_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_shotlist_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Wedding Video Shot List Task Setup Complete ==="
echo ""
echo "📝 SCENARIO:"
echo "   You're a wedding videographer preparing for the Martinez-Chen wedding."
echo "   Raw shooting notes are scattered in: ~/Desktop/shot_notes_raw.txt"
echo "   Your goal: Create a professional, organized shot list document."
echo ""
echo "📋 REQUIREMENTS:"
echo "   1. Add a formatted title (e.g., 'Martinez-Chen Wedding | Shot List')"
echo "   2. Organize shots into timeline sections:"
echo "      - Pre-Ceremony (Getting Ready)"
echo "      - Ceremony"
echo "      - Family Formals"
echo "      - Couple Portraits"
echo "      - Reception"
echo "      - Detail Shots (throughout day)"
echo "   3. Mark priority/critical shots in BOLD"
echo "   4. Use bullet points or numbered lists for shots"
echo "   5. Add at least 2-3 production notes or creative shots beyond raw notes"
echo "   6. Save the document (Ctrl+S)"
echo ""
echo "🎯 SUCCESS CRITERIA:"
echo "   - Professional formatting with clear sections"
echo "   - At least 18 total shots organized logically"
echo "   - Priority shots clearly marked"
echo "   - Production thinking demonstrated"
echo ""
echo "💡 TIP: Open the raw notes file from Desktop to reference while building the shot list."