#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Flashcard Import Formatter Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial messy vocabulary document
DOC_PATH="$WORKSPACE_DIR/spanish_vocab_notes.docx"

cat > /tmp/create_vocab_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add title
title = doc.add_paragraph("Spanish Vocabulary Notes - Trip Preparation")
title.runs[0].bold = True
title.runs[0].font.size = Pt(14)

doc.add_paragraph("")
doc.add_paragraph("(Compiled from various sources - need to format for Anki import!)")
doc.add_paragraph("")

# Add messy vocabulary entries with inconsistent formatting
doc.add_paragraph("restaurant = restaurante")
doc.add_paragraph("to eat - comer")
doc.add_paragraph("hotel")
doc.add_paragraph("  a place to sleep, lodging")
doc.add_paragraph("beach (la playa)")
doc.add_paragraph("¿Dónde está el baño? means Where is the bathroom?")
doc.add_paragraph("airport = aeropuerto")
doc.add_paragraph("taxi - taxi (same!)")
doc.add_paragraph("water/agua")
doc.add_paragraph("I would like... - Quisiera...")
doc.add_paragraph("How much does it cost? / ¿Cuánto cuesta?")

doc.add_paragraph("")
doc.add_paragraph("---")
doc.add_paragraph("TODO: Format as: English[TAB]Spanish[TAB]Example (optional)")
doc.add_paragraph("Need header row: English[TAB]Spanish[TAB]Example")
doc.add_paragraph("Remove all those (parenthetical notes)")

doc.save(sys.argv[1])
print(f"Vocabulary document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_vocab_doc.py
python3 /tmp/create_vocab_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Vocabulary document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_flashcard_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_flashcard_task.log || true
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

echo "=== Flashcard Import Formatter Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review the messy vocabulary notes"
echo "  2. Reformat into tab-delimited structure:"
echo "     English[TAB]Spanish[TAB]Example"
echo "  3. Add header row at top"
echo "  4. Clean up all entries:"
echo "     - Replace '=', '-', '/' with TAB characters"
echo "     - Consolidate multi-line entries to single lines"
echo "     - Remove parenthetical notes: (la playa), (same!)"
echo "     - Preserve special characters: á, é, ñ, ¿, ¡"
echo "  5. Each vocabulary entry should be ONE line with TABs"
echo "  6. Save the document (Ctrl+S)"
echo ""
echo "Expected vocabulary (10 entries):"
echo "  restaurante, comer, hotel, playa, baño, aeropuerto,"
echo "  taxi, agua, Quisiera, cuesta"