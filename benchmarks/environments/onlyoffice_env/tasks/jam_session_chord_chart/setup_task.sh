#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Jam Session Chord Chart Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the starter document with instructions
DOC_PATH="$WORKSPACE_DIR/autumn_groove_chart.docx"

cat > /tmp/create_chord_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Add title and instructions
title = doc.add_paragraph()
title_run = title.add_run("CHORD CHART CREATION TASK")
title_run.bold = True
title_run.font.size = Pt(16)
title.alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_paragraph("")

# Instructions
instructions = doc.add_paragraph()
instructions.add_run("Instructions: ").bold = True
instructions.add_run("Create a professional chord chart for the jazz song 'Autumn Groove'. Your vocalist needs it in E♭ Major (transposed from G Major).")

doc.add_paragraph("")

# Reference section
ref_heading = doc.add_paragraph()
ref_heading.add_run("REFERENCE - Original Progression (G Major):").bold = True

doc.add_paragraph("You recorded this progression in G major:")
doc.add_paragraph("| Gmaj7  | Em7    | Am7    | D7     |")
doc.add_paragraph("| Gmaj7  | Em7    | Am7    | D7     |")
doc.add_paragraph("| Cmaj7  | Cm7    | Bm7    | E7     |")
doc.add_paragraph("| Am7    | D7     | Gmaj7  | Gmaj7  |")

doc.add_paragraph("")

# Task requirements
task_heading = doc.add_paragraph()
task_heading.add_run("YOUR TASK:").bold = True

doc.add_paragraph("1. Create a title block at the top with:")
doc.add_paragraph("   • Song Title: Autumn Groove")
doc.add_paragraph("   • Key: E♭ Major")
doc.add_paragraph("   • Tempo: Medium Swing (♩= 120)")

doc.add_paragraph("")

doc.add_paragraph("2. Create a table-based chord chart with the progression TRANSPOSED to E♭ Major")
doc.add_paragraph("   • Transpose each chord down a major third (G → E♭)")
doc.add_paragraph("   • Use 4 measures per row in your table")
doc.add_paragraph("   • Add section labels: [A], [A] (repeat), [B] (bridge), [A] (return)")

doc.add_paragraph("")

doc.add_paragraph("3. Format for readability:")
doc.add_paragraph("   • Center chords in table cells")
doc.add_paragraph("   • Use clear table borders for measure divisions")
doc.add_paragraph("   • Bold section labels")

doc.add_paragraph("")

doc.add_paragraph("4. Delete these instructions when done and save the document (Ctrl+S)")

doc.add_paragraph("")
doc.add_paragraph("=" * 60)
doc.add_paragraph("BEGIN YOUR CHORD CHART BELOW THIS LINE:")
doc.add_paragraph("=" * 60)
doc.add_paragraph("")

# Add some blank space for working
for _ in range(3):
    doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Chord chart starter document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_chord_doc.py
python3 /tmp/create_chord_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Starter document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_chord_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_chord_task.log || true
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

echo "=== Jam Session Chord Chart Task Setup Complete ==="
echo "📝 Task Summary:"
echo "  • Create a professional chord chart for 'Autumn Groove'"
echo "  • Transpose from G Major to E♭ Major (down a major third)"
echo "  • Include: Title block, Key, Tempo marking"
echo "  • Format as a table with 4 measures per row"
echo "  • Add section labels: [A], [B]"
echo "  • Save as autumn_groove_chart.docx"
echo ""
echo "Transposition guide (examples):"
echo "  Gmaj7 → E♭maj7 | Em7 → Cm7 | Am7 → Fm7 | D7 → B♭7"
echo "  Cmaj7 → A♭maj7 | Bm7 → Gm7 | E7 → C7"