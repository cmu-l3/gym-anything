#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Escape Room Puzzle Flow Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial messy document
DOC_PATH="$WORKSPACE_DIR/alchemist_room_notes.docx"

cat > /tmp/create_escape_room_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add messy, scattered notes as they would appear in real working document
doc.add_paragraph("ALCHEMIST ROOM IDEAS - DRAFT", style='Heading 1')
doc.add_paragraph("")

doc.add_paragraph("Puzzle 1: Bookshelf code - players find books with symbols on spines, enter 4-digit code on lock. Opens drawer with UV light. Should take about 10min? Maybe less if they're smart.")
doc.add_paragraph("")

doc.add_paragraph("Puzzle 2: UV light reveals invisible symbols on wall - maybe on potion bottles?? need to figure this out. These symbols give clues to crystal order.")
doc.add_paragraph("")

doc.add_paragraph("Crystal Puzzle - three colored crystals (red, blue, green) need to be placed on altar pedestals in correct order based on UV symbols. Opens cabinet with ingredients. Josh says this is too easy, Emma disagrees.")
doc.add_paragraph("")

doc.add_paragraph("Ingredient Mixing - players mix potions following recipe found in opened cabinet. Recipe: 2 parts moonflower, 1 part dragon scale, 3 parts phoenix ash. Wrong mix = harmless smoke effect. Right mix glows blue and opens secret panel in wall. TIME: 8-12 min depending on group size")
doc.add_paragraph("")

doc.add_paragraph("SECRET PANEL: has the master key? or another clue? DECIDE THIS - maybe contains part of final puzzle instead")
doc.add_paragraph("")

doc.add_paragraph("Locked Chest - needs 4-digit code from somewhere. Contains telescope lens. But where does code come from? Maybe bookshelf sequence?")
doc.add_paragraph("")

doc.add_paragraph("Telescope puzzle - aim telescope at correct constellation on ceiling using lens from chest. When aligned properly, unlocks drawer with philosopher's stone fragment. Cool lighting effect! (15 minutes - Emma thinks too long)")
doc.add_paragraph("")

doc.add_paragraph("FINAL: Philosopher's Stone assembly - need to combine items: stone fragment from telescope, crystal from ingredient puzzle, and... something else? Placing all items on central pedestal in correct order opens exit door.")
doc.add_paragraph("")

doc.add_paragraph("RESET NOTES:")
doc.add_paragraph("- Reset bookshelf books to starting positions (mark with tape)")
doc.add_paragraph("- Replace potion bottles on shelf")
doc.add_paragraph("- Smoke machine needs refill every 4 games")
doc.add_paragraph("- UV light batteries - check weekly")
doc.add_paragraph("")

doc.add_paragraph("ISSUES & QUESTIONS:")
doc.add_paragraph("- Josh said telescope should be later in sequence, but Emma thinks it's too hard for early puzzle")
doc.add_paragraph("- Crystal puzzle might be too easy? Add a step where they need to decode symbols first?")
doc.add_paragraph("- What's the actual win condition? Door opens or lights flash or both?")
doc.add_paragraph("- Missing timing estimate for UV light puzzle")
doc.add_paragraph("")

doc.add_paragraph("COMMON PLAYER MISTAKES (from beta testing):")
doc.add_paragraph("People try to use UV light on everything, waste time")
doc.add_paragraph("Ingredient mixing - they don't read recipe carefully, mix random amounts")

doc.save(sys.argv[1])
print(f"Escape room notes document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_escape_room_doc.py
python3 /tmp/create_escape_room_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_escape_room_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_escape_room_task.log || true
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

echo "=== Escape Room Puzzle Flow Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Transform the messy notes into a professional Master Flow Document"
echo "  2. Add proper title: 'The Alchemist's Laboratory - Master Flow Document'"
echo "  3. Create sections with proper headings:"
echo "     - Room Overview"
echo "     - Puzzle Flow Map (include dependency table)"
echo "     - Individual Puzzle Details (all 8 puzzles)"
echo "     - Reset Checklist (at least 6 items)"
echo "     - Common Issues & Hints (at least 3 entries)"
echo "  4. Complete all puzzle information (name, description, solution, dependencies, time, reset)"
echo "  5. Resolve contradictions and add design notes for unresolved issues"
echo "  6. Save the document (Ctrl+S)"