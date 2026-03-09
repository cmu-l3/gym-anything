#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up IEP Meeting Prep Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document with unstructured notes
DOC_PATH="$WORKSPACE_DIR/IEP_Meeting_Prep.docx"

cat > /tmp/create_iep_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add unstructured content that needs to be organized
content = """IEP meeting next week for Elijah. Need to get organized.

Test Scores:
- WIAT Reading Comprehension: 78 standard score (December 2024)
- Fountas & Pinnell: Level K, expected Level P (January 2025)  
- DIBELS Oral Reading Fluency: 45 words/min, benchmark is 87 (February 2025)

Things I'm worried about:
Teacher says he's "trying hard" but reading hasn't improved much
He still can't decode multisyllabic words consistently
Gets frustrated during independent reading time and avoids it
Accommodations from last year's IEP don't seem to be happening regularly

Accommodations I want:
Extended time on tests
Books on audio
Preferential seating  
Use of text-to-speech software
Frequent breaks during reading tasks
Visual supports for phonics rules

Goal idea:
"Elijah will improve his reading skills."
"""

# Split by lines and add as paragraphs
for line in content.split('\n'):
    para = doc.add_paragraph(line)
    # Set default font size
    for run in para.runs:
        run.font.size = Pt(11)

doc.save(sys.argv[1])
print(f"IEP document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_iep_doc.py
python3 /tmp/create_iep_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_iep_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_iep_task.log || true
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

echo "=== IEP Meeting Prep Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Add document title: 'IEP Meeting Preparation: Elijah Rodriguez' (18pt, bold, centered)"
echo "  2. Create section headings (14pt, bold):"
echo "     - Current Performance Data"
echo "     - Areas of Concern"
echo "     - Requested Accommodations"
echo "     - Proposed Measurable Goal"
echo "  3. In 'Current Performance Data': Create a table with 4 columns and organize test scores"
echo "  4. In 'Areas of Concern': Convert to numbered list (3+ items)"
echo "  5. In 'Requested Accommodations': Create bulleted list with bold names (4+ items)"
echo "  6. In 'Proposed Measurable Goal': Write SMART goal with bold skill, measurable criterion, timeframe"
echo "  7. Save the document (Ctrl+S)"