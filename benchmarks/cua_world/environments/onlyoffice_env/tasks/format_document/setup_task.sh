#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Format Document Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document
DOC_PATH="$WORKSPACE_DIR/sample_document.docx"

cat > /tmp/create_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Add paragraphs that need to be formatted
doc.add_paragraph("ONLYOFFICE Document Editor")
doc.add_paragraph("")
doc.add_paragraph("This document needs formatting. Please apply the following changes:")
doc.add_paragraph("")
doc.add_paragraph("Make this text bold")
doc.add_paragraph("")
doc.add_paragraph("Make this text italic")
doc.add_paragraph("")
doc.add_paragraph("Important Notice")
doc.add_paragraph("")
doc.add_paragraph("This is regular text that should remain unchanged.")

doc.save(sys.argv[1])
print(f"Document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_doc.py
python3 /tmp/create_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_doc_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_doc_task.log || true
    exit 1
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    exit 1
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Format Document Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Find the paragraph 'Make this text bold'"
echo "  2. Select it and make it bold (Ctrl+B)"
echo "  3. Find the paragraph 'Make this text italic'"
echo "  4. Select it and make it italic (Ctrl+I)"
echo "  5. Find 'Important Notice' and make it Heading 1 style"
echo "  6. Save the document (Ctrl+S)"
