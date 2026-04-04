#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Household Emergency Binder Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document (empty starter document)
DOC_PATH="$WORKSPACE_DIR/emergency_reference.docx"

cat > /tmp/create_emergency_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, RGBColor
import sys

# Create a minimal starting document with just instructions
doc = Document()

# Add minimal starting content - just a placeholder
intro = doc.add_paragraph()
intro.add_run("Emergency Reference Document").bold = True
intro.add_run("\n\nCreate a comprehensive emergency preparedness document with the following sections:\n")

doc.add_paragraph("1. Emergency Contacts (use a table)")
doc.add_paragraph("2. Family Meeting Points")
doc.add_paragraph("3. Critical Documents Checklist")
doc.add_paragraph("4. Pet Information")
doc.add_paragraph("5. Medical Information (use a table)")
doc.add_paragraph("6. Evacuation Routes")

doc.add_paragraph("\nFormat the main title as: HOUSEHOLD EMERGENCY REFERENCE")
doc.add_paragraph("Make all section headings bold and prominent.")

doc.save(sys.argv[1])
print(f"Emergency document template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_emergency_doc.py
python3 /tmp/create_emergency_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Emergency reference document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_emergency_binder_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_emergency_binder_task.log || true
    # Don't exit - let the task continue in case it starts later
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # Don't exit - let the task continue
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Household Emergency Binder Task Setup Complete ==="
echo ""
echo "📋 TASK SCENARIO:"
echo "You recently experienced an evacuation scare (wildfire/hurricane warning) and realized"
echo "you were completely unprepared. You need to create a printed emergency reference binder"
echo "that can be grabbed in 30 seconds during a crisis."
echo ""
echo "📝 REQUIRED SECTIONS (create from scratch or replace template):"
echo "  1. Main Title: 'HOUSEHOLD EMERGENCY REFERENCE' (bold, 16pt, centered)"
echo "  2. EMERGENCY CONTACTS section with table:"
echo "     - Columns: Name | Relationship | Phone Number | Notes"
echo "     - At least 4 contacts (family, neighbors, emergency services, etc.)"
echo "  3. FAMILY MEETING POINTS section:"
echo "     - Primary location with address"
echo "     - Secondary location with address"
echo "  4. CRITICAL DOCUMENTS CHECKLIST:"
echo "     - List important documents and storage locations"
echo "     - Examples: birth certificates, insurance policies, deeds, passports"
echo "  5. PET INFORMATION section:"
echo "     - Pet names, medications, vet contact info"
echo "  6. MEDICAL INFORMATION section with table:"
echo "     - Columns: Family Member | Allergies | Medications | Conditions"
echo "     - Include at least 2 family members"
echo "  7. EVACUATION ROUTES section:"
echo "     - Primary and alternate routes with brief notes"
echo ""
echo "✅ FORMATTING REQUIREMENTS:"
echo "  - Main title must be bold, size 16pt, and centered"
echo "  - Section headings must be bold, size 14pt"
echo "  - Use at least 2 tables (Emergency Contacts + Medical Info)"
echo "  - Use bold/italic for emphasis on critical information"
echo ""
echo "💾 When complete, save the document (Ctrl+S)"