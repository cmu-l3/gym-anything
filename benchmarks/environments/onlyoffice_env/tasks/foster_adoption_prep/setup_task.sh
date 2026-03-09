#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Foster Adoption Prep Task ==="

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

# Create the foster notes text file with scattered information
NOTES_PATH="$NOTES_DIR/foster_notes.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
=================================================
FOSTER CAT NOTES - Second Chance Cat Rescue
Emma's Notes for Adoption Event (Saturday)
=================================================

WHISKERS
--------
Big orange tabby boy, super friendly!
Came in: October 22 (8 weeks ago now)
Neutered: Yes
Age: Adult male (around 3-4 years)
Vaccines: All up to date, rabies done
Behavior: Gets along great with other cats, very social
Status: READY FOR ADOPTION NOW

LUNA
----
Young tabby girl, still a bit shy
Arrived: November 25 (about 3 weeks)
Spayed: Yes, done before intake
Age: 8 months old (young adult)
Behavior: Hides when strangers visit, needs patient owner
Still working on socialization
Status: Needs more time, not quite ready yet

MISTER
------
Sweet senior gentleman, has special needs
Intake date: November 4 (6 weeks in foster)
Neutered: Yes
Age: 12 years old (senior)
Medical: DIABETIC - managed with insulin 2x daily
Behavior: Extremely gentle, loves lap time
Vet says: Stable on current insulin dose
Status: Ready for experienced adopter who can handle diabetes

PATCHES
-------
Calico female, currently sick
Just arrived: December 6 (10 days ago)
Spayed: Yes
Age: Adult female (approx 2-3 years)
Medical: Has URI (upper respiratory infection)
Started antibiotic (Clavamox) yesterday
Vet recheck scheduled: 5 days from now
Status: NOT READY - still under treatment

SIMBA
-----
Adorable orange kitten, so playful!
Came in: October 22 (same day as Whiskers, 8 weeks ago)
Age: 4 months old (kitten)
Neutered: Last week (December 9), healing perfectly
Behavior: Super energetic, playful, needs active home
Status: READY TO GO!

SHADOW
------
Beautiful black adult female
Arrived: November 11 (5 weeks in foster)
Spayed: Yes
Age: Adult (3 years)
Medical: FIV POSITIVE (needs indoor-only home)
Behavior: Absolute sweetheart, very affectionate
Special note: FIV+ cats can live normal lives indoors
Status: Ready for special placement (experienced owner)

=================================================
NOTES TO SELF:
- Need to organize this into spreadsheet format
- Adoption coordinator wants to see at-a-glance readiness
- Highlight which cats are ready NOW vs need more time
- Include weeks in foster (calculate from today's date)
=================================================
NOTESEOF

chown ga:ga "$NOTES_PATH"
echo "✅ Foster notes created at: $NOTES_PATH"

# Create a blank spreadsheet
SHEET_PATH="$WORKSPACE_DIR/foster_cats_adoption.xlsx"

cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Foster Cats"

# Add a helpful note in the first cell
ws['A1'] = "Foster Cat Adoption Readiness Tracker"
ws['A2'] = "(See foster_notes.txt in Documents folder for cat information)"
ws['A3'] = ""

# Make first cell bold and larger if possible
try:
    from openpyxl.styles import Font
    ws['A1'].font = Font(bold=True, size=14)
    ws['A2'].font = Font(italic=True, size=10)
except:
    pass

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_foster_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_foster_task.log || true
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

echo "=== Foster Adoption Prep Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "You are helping Emma organize foster cat data for an adoption event."
echo "Her notes are scattered in: /home/ga/Documents/foster_notes.txt"
echo ""
echo "📝 TASK:"
echo "Create a structured spreadsheet to track adoption readiness for 6 cats:"
echo "  - Whiskers, Luna, Mister, Patches, Simba, Shadow"
echo ""
echo "Required columns:"
echo "  1. Cat Name"
echo "  2. Age Category (Kitten/Young Adult/Adult/Senior)"
echo "  3. Sex (Male/Female)"
echo "  4. Weeks in Foster (calculate from arrival dates in notes)"
echo "  5. Medical Status (Healthy/Special Needs/Treatment Pending)"
echo "  6. Behavioral Notes (brief description)"
echo "  7. Adoption Readiness (Ready Now/Needs More Time/Special Placement)"
echo ""
echo "💡 TIPS:"
echo "  - Read foster_notes.txt carefully to extract all information"
echo "  - Calculate weeks in foster (today is December 16, 2024)"
echo "  - Categorize readiness based on medical status and behavior"
echo "  - Save with Ctrl+S when done"
echo ""