#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Apartment Sublet Handoff Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document with instructions
DOC_PATH="$WORKSPACE_DIR/sublet_handoff.docx"

cat > /tmp/create_sublet_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Add title
title = doc.add_paragraph()
title_run = title.add_run("APARTMENT SUBLET HANDOFF DOCUMENT")
title_run.bold = True
title_run.font.size = Pt(16)
title.alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_paragraph("")

# Add instruction box
instruction = doc.add_paragraph()
instruction_run = instruction.add_run("TASK: Create a comprehensive sublet handoff document with the following sections:")
instruction_run.font.size = Pt(11)
instruction_run.italic = True

doc.add_paragraph("")

# Add checklist
checklist = [
    "1. PARTIES & PROPERTY - Include: Primary Tenant 'Sarah Chen', Subletter 'Marcus Rodriguez', Address '742 Maple Street, Unit 3B, Portland, OR 97214', Dates 'June 1, 2024 - August 31, 2024'",
    "2. FINANCIAL ARRANGEMENTS - Include: Rent $1,450, Deposit $800, utilities, payment method",
    "3. APARTMENT CONDITION DOCUMENTATION - List at least 3 pre-existing conditions with descriptions",
    "4. PRACTICAL INFORMATION - Include at least 4 items (WiFi, trash schedule, parking, heating/AC, etc.)",
    "5. IMPORTANT CONTACTS - List at least 3 contacts (tenant, landlord, maintenance, etc.)",
    "6. RULES & EXPECTATIONS - Include at least 3 rules (smoking, guests, pets, noise, etc.)"
]

for item in checklist:
    p = doc.add_paragraph(item)
    p.style = 'List Bullet'

doc.add_paragraph("")
doc.add_paragraph("Delete these instructions and create your document below:")
doc.add_paragraph("")
doc.add_paragraph("=" * 60)
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_sublet_doc.py
python3 /tmp/create_sublet_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document template created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_sublet_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_sublet_task.log || true
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

echo "=== Apartment Sublet Handoff Task Setup Complete ==="
echo "📝 Task: Create a comprehensive sublet handoff document"
echo ""
echo "Required Sections (6 total):"
echo "  1. PARTIES & PROPERTY"
echo "     - Primary Tenant: Sarah Chen"
echo "     - Subletter: Marcus Rodriguez"
echo "     - Address: 742 Maple Street, Unit 3B, Portland, OR 97214"
echo "     - Dates: June 1, 2024 - August 31, 2024"
echo ""
echo "  2. FINANCIAL ARRANGEMENTS"
echo "     - Monthly rent: \$1,450"
echo "     - Security deposit: \$800 (refundable)"
echo "     - Utilities responsibility"
echo "     - Payment method and due date"
echo ""
echo "  3. APARTMENT CONDITION DOCUMENTATION"
echo "     - At least 3 pre-existing conditions"
echo ""
echo "  4. PRACTICAL INFORMATION"
echo "     - At least 4 items (WiFi, trash, parking, etc.)"
echo ""
echo "  5. IMPORTANT CONTACTS"
echo "     - At least 3 contacts"
echo ""
echo "  6. RULES & EXPECTATIONS"
echo "     - At least 3 rules"
echo ""
echo "Save the document when complete (Ctrl+S)"