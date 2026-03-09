#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up IEP Accommodation Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document with messy notes
DOC_PATH="$WORKSPACE_DIR/504_review_prep.docx"

cat > /tmp/create_504_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add title
title = doc.add_paragraph("504 meeting tomorrow notes")
title_format = title.runs[0].font
title_format.size = Pt(14)

doc.add_paragraph("")

# Add unformatted, messy notes (simulating parent's quick typing)
doc.add_paragraph("Current accommodations - extended time on tests and quizzes, preferential seating near front, breaks allowed when needed, copy of class notes provided")

doc.add_paragraph("")

doc.add_paragraph("Problems - Mr. Harrison math class Oct 15 didn't give extended time on quiz, said he forgot. Emma got 67% but ran out of time, only finished 8 of 12 problems. Oct 22 same thing happened on chapter test.")

doc.add_paragraph("")

doc.add_paragraph("Ms. Rodriguez English accommodations working well, very consistent.")

doc.add_paragraph("")

doc.add_paragraph("PE - Coach Williams Nov 3 made Emma run full mile even though she asked for break, very embarrassed in front of class. Plan says \"modified PE expectations\".")

doc.add_paragraph("")

doc.add_paragraph("Science Mrs. Patel Oct 28 Emma asked for notes, teacher said \"just pay better attention\" refused to provide copy. Emma failed quiz next day because missing key info.")

doc.add_paragraph("")

doc.add_paragraph("Need to request - noise canceling headphones for tests, permission to use fidget tools during class, option to type long assignments instead of handwrite")

doc.save(sys.argv[1])
print(f"Document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_504_doc.py
python3 /tmp/create_504_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_504_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_504_task.log || true
    # Don't exit - the task might still start
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # Don't exit - window might appear later
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== IEP Accommodation Tracker Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create section structure with BOLD headings:"
echo "     - 'Current 504 Accommodations'"
echo "     - 'Implementation Concerns'"
echo "     - 'Requested Modifications'"
echo ""
echo "  2. Under 'Current 504 Accommodations':"
echo "     - Convert accommodation list to bullet points"
echo "     - Each accommodation on separate line"
echo ""
echo "  3. Under 'Implementation Concerns':"
echo "     - Create a 4-column table: Date | Teacher/Class | Issue | Impact"
echo "     - Add rows for Harrison (Oct 15, Oct 22), Williams (Nov 3), Patel (Oct 28)"
echo ""
echo "  4. Under 'Requested Modifications':"
echo "     - Format as bullet points"
echo "     - Include headphones, fidget tools, typing option"
echo ""
echo "  5. Format teacher names (Harrison, Williams, Patel, Rodriguez) as BOLD"
echo ""
echo "  6. Save the document (Ctrl+S)"