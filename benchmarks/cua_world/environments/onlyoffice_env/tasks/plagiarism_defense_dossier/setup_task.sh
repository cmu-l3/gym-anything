#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Plagiarism Defense Dossier Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank document for the task
DOC_PATH="$WORKSPACE_DIR/integrity_defense.docx"

cat > /tmp/create_defense_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

# Create a blank document with minimal instruction
doc = Document()

# Add a simple instruction paragraph that the agent should replace
doc.add_paragraph("Academic Integrity Defense Document")
doc.add_paragraph("")
doc.add_paragraph("Instructions: Create a professional defense document with the following sections:")
doc.add_paragraph("1. Title: 'Academic Integrity Defense: Authenticity of Term Paper' (bold, 16pt, centered)")
doc.add_paragraph("2. Student information (Name: Jordan Martinez, Student ID: 847392, Course: SOC 301, Date: March 15, 2024)")
doc.add_paragraph("3. Table showing draft progression with 4 columns and 4 rows")
doc.add_paragraph("4. Section: 'Explanation of Quality Improvement' with explanation paragraph")
doc.add_paragraph("5. Section: 'Supporting Evidence' with bulleted list")
doc.add_paragraph("")
doc.add_paragraph("You may delete these instructions and create the document from scratch.")

doc.save(sys.argv[1])
print(f"Defense document template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_defense_doc.py
python3 /tmp/create_defense_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document template created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_defense_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_defense_task.log || true
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

echo "=== Plagiarism Defense Dossier Task Setup Complete ==="
echo "📝 Task Requirements:"
echo "  1. Title: 'Academic Integrity Defense: Authenticity of Term Paper' (bold, 16pt, centered)"
echo "  2. Student Info: Jordan Martinez, ID: 847392, Course: SOC 301, Date: March 15, 2024"
echo "  3. Table with draft progression (4 rows × 4 columns):"
echo "     - Headers: Draft Version | Date Completed | Word Count | Key Changes"
echo "     - Draft 1 | Feb 10, 2024 | 2,800 | Initial outline and literature review"
echo "     - Draft 2 | Feb 24, 2024 | 4,100 | Added case studies, weak argumentation"
echo "     - Final Draft | March 8, 2024 | 4,950 | Strengthened argument after writing center help"
echo "  4. Section: 'Explanation of Quality Improvement' (bold, 14pt) with paragraph about:"
echo "     - Writing Center visits (Feb 26, March 2) with tutor Sarah Chen"
echo "     - Additional sources from librarian (Feb 28)"
echo "     - Legitimate academic support explanation"
echo "  5. Section: 'Supporting Evidence' (bold, 14pt) with bulleted list:"
echo "     - Writing Center visit receipts"
echo "     - Draft files with metadata"
echo "     - Browser history"
echo "     - Email correspondence with Professor"
echo "  6. Save as: /home/ga/Documents/TextDocuments/integrity_defense.docx"