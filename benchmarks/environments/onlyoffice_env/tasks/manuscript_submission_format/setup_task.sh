#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Manuscript Submission Format Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial draft document (improperly formatted)
DRAFT_PATH="$WORKSPACE_DIR/last_train_home_draft.docx"

cat > /tmp/create_manuscript_draft.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Set improper margins (not 1 inch)
section = doc.sections[0]
section.top_margin = Inches(1.25)
section.bottom_margin = Inches(1.25)
section.left_margin = Inches(1.0)
section.right_margin = Inches(1.0)

# Story content - improperly formatted
story_paragraphs = [
    "The old station stood silent at midnight. Emma checked her watch again—11:47 PM. The last train was due at 11:55, and she couldn't miss it.",
    "",
    "She paced the empty platform, her suitcase wheels clicking against the concrete. Three years in this town had been enough. Maybe too much.",
    "",
    "A distant whistle cut through the cold air. The train was coming.",
    "",
    "She thought about Michael, probably asleep by now, unaware she was leaving. The note on the kitchen table would have to be enough. It explained everything and nothing at the same time.",
    "",
    "",  # Scene break location (but not marked)
    "",
    "The conductor's voice crackled over the intercom. \"Last stop before the border. Last chance to turn back.\"",
    "",
    "Emma gripped her ticket tighter. There was no turning back now. The decision had been made months ago, in small increments of disappointment and silence.",
    "",
    "Through the window, she watched the familiar streets blur into darkness. Somewhere behind her was everything she'd ever known. Ahead was everything she'd hoped for.",
    "",
    "The train picked up speed, and Emma finally exhaled."
]

# Add content with POOR formatting (what needs to be fixed)
for i, para_text in enumerate(story_paragraphs):
    if para_text:  # Non-empty paragraphs
        p = doc.add_paragraph(para_text)
        
        # Mixed fonts and sizes (inconsistent and wrong)
        for run in p.runs:
            if i % 3 == 0:
                run.font.name = 'Arial'  # Wrong font
                run.font.size = Pt(11)
            else:
                run.font.name = 'Calibri'  # Also wrong
                run.font.size = Pt(11)
        
        # Single spacing (WRONG - should be double)
        p.paragraph_format.line_spacing = 1.0
        
        # No first-line indent (WRONG - should have 0.5")
        p.paragraph_format.first_line_indent = Inches(0.0)
    else:
        # Add empty paragraph for spacing
        doc.add_paragraph()

# NO title page (needs to be added)
# NO headers (need to be added)
# NO proper scene break markers (need to be added)

doc.save(sys.argv[1])
print(f"Draft manuscript created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_manuscript_draft.py
python3 /tmp/create_manuscript_draft.py "$DRAFT_PATH"
chown ga:ga "$DRAFT_PATH"

echo "✅ Draft manuscript created at: $DRAFT_PATH"

# Launch ONLYOFFICE with the draft document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DRAFT_PATH' > /tmp/onlyoffice_manuscript_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_manuscript_task.log || true
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

echo "=== Manuscript Submission Format Task Setup Complete ==="
echo ""
echo "📝 TASK: Format manuscript for literary magazine submission"
echo ""
echo "Current draft issues:"
echo "  ❌ No title page"
echo "  ❌ Wrong font (Arial/Calibri instead of Courier New/Times New Roman)"
echo "  ❌ Wrong size (11pt instead of 12pt)"
echo "  ❌ Single-spaced (should be double-spaced)"
echo "  ❌ No first-line paragraph indents"
echo "  ❌ No headers"
echo "  ❌ Missing scene break markers"
echo ""
echo "Required formatting:"
echo "  1. Insert title page (page 1) with:"
echo "     - Author: Jordan Reeves"
echo "     - Address: 456 Maple Drive, Lincoln, NE 68508"
echo "     - Email: jreeves.writer@email.com"
echo "     - Word count: 2,500 words (upper-right)"
echo "     - Title: THE LAST TRAIN HOME (centered, all caps)"
echo "     - Byline: by Jordan Reeves (centered)"
echo ""
echo "  2. Format entire document:"
echo "     - Font: 12pt Courier New (or Times New Roman)"
echo "     - Line spacing: Double (2.0)"
echo "     - Margins: 1 inch all sides"
echo "     - First-line indent: 0.5 inches"
echo ""
echo "  3. Add header (pages 2+ only, NOT on title page):"
echo "     - Format: 'Reeves / LAST TRAIN HOME / [page number]'"
echo "     - Position: upper-right"
echo ""
echo "  4. Add scene breaks:"
echo "     - Centered '#' where there are double line breaks"
echo ""
echo "  5. Save as: last_train_home_submission.docx"
echo ""