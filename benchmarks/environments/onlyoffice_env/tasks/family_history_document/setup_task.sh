#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Family History Document Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank starter document with minimal instructions
DOC_PATH="$WORKSPACE_DIR/FamilyHistory.docx"

cat > /tmp/create_family_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Add a simple instruction paragraph
doc.add_paragraph("Family History Document - To Be Completed")
doc.add_paragraph("")
doc.add_paragraph("Instructions: Create a formatted family history document with:")
doc.add_paragraph("• Title: Anderson-Martinez Family History (Heading 1, centered)")
doc.add_paragraph("• Section 1: Maternal Line: The Martinez Family (Heading 2)")
doc.add_paragraph("• Section 2: Paternal Line: The Anderson Family (Heading 2)")
doc.add_paragraph("• Content about Rosa Martinez, Carlos Martinez, James Anderson, Dorothy Anderson (names in bold)")
doc.add_paragraph("• A table showing family relationships")
doc.add_paragraph("")
doc.add_paragraph("--- Start your document below this line ---")
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_family_doc.py
python3 /tmp/create_family_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_family_doc.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_family_doc.log || true
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

echo "=== Family History Document Task Setup Complete ==="
echo ""
echo "📝 Task Requirements:"
echo "  1. Create title 'Anderson-Martinez Family History' with Heading 1 style, centered"
echo "  2. Create section 'Maternal Line: The Martinez Family' with Heading 2 style"
echo "  3. Write about Rosa Martinez (born ~1928) marrying Carlos Martinez in 1947"
echo "     - Make names Rosa Martinez and Carlos Martinez BOLD"
echo "     - Mention they raised four children and ran a grocery store"
echo "  4. Create section 'Paternal Line: The Anderson Family' with Heading 2 style"
echo "  5. Write about James Anderson (born 1925) meeting Dorothy Anderson in 1949"
echo "     - Make names James Anderson and Dorothy Anderson BOLD"
echo "     - Mention they moved to California in 1952"
echo "  6. Create a table with 3 columns: Person | Born | Relationship"
echo "     - Row 1: Rosa Martinez | ~1928 | Maternal Grandmother"
echo "     - Row 2: James Anderson | 1925 | Paternal Grandfather"
echo "  7. Save the document (Ctrl+S)"
echo ""