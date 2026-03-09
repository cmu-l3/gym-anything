#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Escape Room Hint System Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy input text file with unorganized hint information
DRAFT_PATH="$WORKSPACE_DIR/escape_room_hints_draft.txt"

cat > "$DRAFT_PATH" << 'TXTEOF'
ALCHEMIST LAB - Hint Notes (DRAFT - needs organization!)
==========================================================

** The Locked Journal **
- combination lock on old leather journal
- Hint idea: look around the room for numbers
- Hint idea: check the bookshelf titles carefully
- Hint idea: the spines show years, add the last digits
- NOTE: combination is years 1642, 1789, 1905 -> 6+4+2+7+8+9+9+0+5 = 50, but they need to figure out the math
- ANSWER: 50

periodic table wall puzzle:
Elements spell out a word if you use atomic numbers
hint - count the highlighted elements
hint - it's not the element names, use the NUMBER
hint - highlighted are: H(1), E(5), L(3), I(9), O(8), S(16)... wait that doesn't work
Actually: use first letter of element names! Highlighted: Helium Oxygen Phosphorus Einsteinium = HOPE
REAL ANSWER: HOPE

---The Distillation Apparatus---
Colored liquids need to be mixed in correct order
Red + Blue = Purple (first step)
Yellow + Purple = Brown (second step)  
Green goes last
HINTS TO GIVE:
"What happens when you mix colors?" (gentle)
"Try combining two at a time, not all at once" (medium)
"Red and blue first, then add yellow to the result, green goes in last" (almost giving it away)
Solution: Red->Blue->Yellow->Green sequence

4. Constellation Map
There's a star map on the ceiling with constellations
HINT 1: Look up (literally)
HINT 2: The highlighted stars form letters when connected
HINT 3: Connect Orion, Cassiopeia, Ursa Major - they spell O-C-U (oh-see-you)
Some groups never look up! Make sure they found the UV flashlight first or they can't see the glow-in-dark stars
ANSWER: OCU

#5 - ancient tome puzzle
Latin phrases scattered around room
"Omnia Vincit Amor" = Love Conquers All
"Carpe Diem" = Seize the Day
"Veni Vidi Vici" = I Came I Saw I Conquered
They need to translate and take first letter: L-S-I
Hints:
- gentle: "These aren't just decorations, they mean something"
- medium: "You might need to translate these phrases"
- direct: "Translate each phrase and use the first letter of the English translation"
ANSWER: LSI

PUZZLE 6: The Final Formula!!!
This is the culminating puzzle - uses answers from previous 5 puzzles
Combination: 50, Word: HOPE, Sequence position: 4, Code: OCU, Letters: LSI
They need to combine them somehow to open the final safe
The safe accepts: 50-HOPE-4-OCU-LSI (in that order)
HINTS:
- "You've collected five pieces of information so far"
- "Try entering them in the order you solved the puzzles"
- "Format: Number-Word-Number-Code-Letters, all your previous answers"
SOLUTION: 50-HOPE-4-OCU-LSI

GENERAL NOTES:
- Always ask groups what specific part they're stuck on
- Wait 3-5 minutes between hints
- Watch the camera feeds
- Don't give hint 3 unless they're almost out of time
TXTEOF

chown ga:ga "$DRAFT_PATH"
echo "✅ Draft hint file created at: $DRAFT_PATH"

# Launch ONLYOFFICE Document Editor with a blank document
# We'll have them create the final document from scratch based on the draft
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors > /tmp/onlyoffice_escape_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_escape_task.log || true
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

echo "=== Escape Room Hint System Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read the messy draft file at: $DRAFT_PATH"
echo "  2. Create a new document with proper structure"
echo "  3. Add header: Title 'The Alchemist's Laboratory - Hint Progression System'"
echo "  4. Add subtitle: 'Game Master Reference Sheet'"
echo "  5. For each of 6 puzzles, create formatted sections with:"
echo "     - Puzzle name (bold, 14pt)"
echo "     - Brief description"
echo "     - Hint 1: Gentle Nudge (label in bold)"
echo "     - Hint 2: Focused Guidance (label in bold)"
echo "     - Hint 3: Direct Assistance (label in bold)"
echo "     - SOLUTION (Emergency Only) (label in bold, red text)"
echo "  6. Add horizontal lines between puzzle sections"
echo "  7. Add footer with GM tips"
echo "  8. Save as: /home/ga/Documents/alchemist_hints_final.docx"
echo ""
echo "The six puzzles are:"
echo "  1. The Locked Journal"
echo "  2. The Periodic Table Wall"
echo "  3. The Distillation Apparatus"
echo "  4. The Constellation Map"
echo "  5. The Ancient Tome"
echo "  6. The Final Formula"