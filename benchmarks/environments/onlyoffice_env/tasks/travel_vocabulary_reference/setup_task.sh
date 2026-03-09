#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Travel Vocabulary Reference Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create initial document with instructions and starter template
DOC_PATH="$WORKSPACE_DIR/spanish_vocab_reference.docx"

cat > /tmp/create_vocab_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, RGBColor
import sys

doc = Document()

# Add title and instructions
title = doc.add_paragraph()
title_run = title.add_run("Spanish Travel Vocabulary Reference")
title_run.font.size = Pt(18)
title_run.bold = True

doc.add_paragraph()

instructions = doc.add_paragraph()
instructions.add_run("Instructions: Organize Spanish vocabulary for your upcoming trip to Spain. Create four sections with clear headings and add relevant vocabulary pairs. Bold the most essential phrases for quick reference.")
instructions_run = instructions.runs[0]
instructions_run.font.size = Pt(10)
instructions_run.italic = True

doc.add_paragraph()
doc.add_paragraph("=" * 60)
doc.add_paragraph()

# Add section prompts (not filled in - agent needs to create content)
doc.add_paragraph("[Create sections below:]")
doc.add_paragraph()
doc.add_paragraph("Section 1: Restaurants & Dining")
doc.add_paragraph("  (Add Spanish-English vocabulary pairs for restaurant situations)")
doc.add_paragraph()

doc.add_paragraph("Section 2: Hotels & Accommodation") 
doc.add_paragraph("  (Add Spanish-English vocabulary pairs for hotel situations)")
doc.add_paragraph()

doc.add_paragraph("Section 3: Directions & Transportation")
doc.add_paragraph("  (Add Spanish-English vocabulary pairs for navigation)")
doc.add_paragraph()

doc.add_paragraph("Section 4: Emergencies & Help")
doc.add_paragraph("  (Add Spanish-English vocabulary pairs for urgent situations)")
doc.add_paragraph()

doc.add_paragraph()
doc.add_paragraph("Remember: Bold the most essential phrases in each section!")

doc.save(sys.argv[1])
print(f"Document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_vocab_doc.py
python3 /tmp/create_vocab_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document template created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_vocab_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_vocab_task.log || true
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

echo "=== Travel Vocabulary Reference Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create/refine four sections with clear headings:"
echo "     - Restaurants & Dining"
echo "     - Hotels & Accommodation"
echo "     - Directions & Transportation"
echo "     - Emergencies & Help"
echo ""
echo "  2. Add Spanish-English vocabulary pairs in each section:"
echo "     Examples:"
echo "       • Una mesa para dos - A table for two"
echo "       • La cuenta, por favor - The check, please"
echo "       • ¿Dónde está...? - Where is...?"
echo "       • Necesito ayuda - I need help"
echo ""
echo "  3. Apply BOLD formatting (Ctrl+B) to essential phrases (2-3 per section)"
echo "     Essential phrases might include:"
echo "       • No hablo español (I don't speak Spanish)"
echo "       • ¿Habla inglés? (Do you speak English?)"
echo "       • Ayuda (Help)"
echo ""
echo "  4. Include at least 15-20 vocabulary items total"
echo "  5. Save the document (Ctrl+S)"