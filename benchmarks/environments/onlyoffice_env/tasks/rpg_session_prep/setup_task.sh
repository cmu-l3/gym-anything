#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up RPG Session Prep Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document with starter template
DOC_PATH="$WORKSPACE_DIR/session_notes.docx"

cat > /tmp/create_rpg_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Add a starter paragraph with instructions
intro = doc.add_paragraph()
intro.add_run("GM Session Notes - Template\n").bold = True
intro.add_run("\nYour task: Create organized session notes for tonight's D&D game.\n\n")
intro.add_run("Required structure:\n")
intro.add_run("1. Title: 'Shadowmere Crypts - Session 7 Notes' (Heading 1, centered)\n")
intro.add_run("2. Section: 'Active Quests' (Heading 2)\n")
intro.add_run("   - Add 2-3 lines describing current quest hooks\n\n")
intro.add_run("3. Section: 'Key NPCs' (Heading 2)\n")
intro.add_run("   - Create a table with 3 columns: Name | Role | Important Info\n")
intro.add_run("   - Add at least 3 NPC entries\n\n")
intro.add_run("4. Section: 'Random Encounters' (Heading 2)\n")
intro.add_run("   - Create a table with 2 columns: Roll (d6) | Encounter\n")
intro.add_run("   - Add at least 3 encounter options (numbered 1-3)\n\n")

doc.add_paragraph("\n--- Start your session notes below this line ---\n")

doc.save(sys.argv[1])
print(f"Document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_rpg_doc.py
python3 /tmp/create_rpg_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_rpg_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_rpg_task.log || true
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

echo "=== RPG Session Prep Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Create a structured GM reference document with:"
echo "  1. Title: 'Shadowmere Crypts - Session 7 Notes' (Heading 1, centered)"
echo "  2. Three sections (Heading 2): Active Quests, Key NPCs, Random Encounters"
echo "  3. Active Quests: 2-3 lines of quest description"
echo "  4. Key NPCs: Table with 3 columns (Name, Role, Info) and 3+ entries"
echo "  5. Random Encounters: Table with 2 columns (Roll, Encounter) and 3+ entries"
echo "  6. Save the document (Ctrl+S)"
echo ""
echo "Tip: Use Insert > Table to create tables. Use Home > Styles to apply headings."