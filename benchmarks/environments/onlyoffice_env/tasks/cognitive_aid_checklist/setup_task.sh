#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Cognitive Aid Checklist Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank document for the task
DOC_PATH="$WORKSPACE_DIR/gas_leak_procedure.docx"

cat > /tmp/create_blank_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

# Create a blank document with just a hint
doc = Document()

# Add a subtle instruction paragraph (which the user should replace/modify)
para = doc.add_paragraph()
run = para.add_run("Emergency Procedure Template\n\n")
run.font.size = Pt(11)

para2 = doc.add_paragraph()
run2 = para2.add_run("[Create your emergency gas leak procedure here]\n\n")
run2.font.size = Pt(11)

para3 = doc.add_paragraph()
run3 = para3.add_run("Remember to:\n")
run3.font.size = Pt(11)

doc.add_paragraph("• Add a clear title")
doc.add_paragraph("• Use numbered steps")
doc.add_paragraph("• Include bold warnings")
doc.add_paragraph("• Add emergency contact information")
doc.add_paragraph("• Use large, readable fonts")

doc.save(sys.argv[1])
print(f"Blank document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_doc.py
python3 /tmp/create_blank_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Blank document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_doc_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_doc_task.log || true
    # Don't exit - task can still proceed
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # Don't exit - task can still proceed
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Cognitive Aid Checklist Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Create an emergency procedure sheet for someone with cognitive impairment"
echo ""
echo "REQUIREMENTS:"
echo "  1. Title: 'Emergency: Gas Leak Procedure' (or similar)"
echo "     → Make it 18pt or larger"
echo "     → Make it BOLD"
echo "     → Center it or make it highly visible"
echo ""
echo "  2. Numbered Steps (at least 5):"
echo "     → Use numbered list format (1, 2, 3...)"
echo "     → Each step should be ONE clear action"
echo "     → Use 14pt font or larger for readability"
echo "     → Examples:"
echo "       1. Do NOT turn on any lights"
echo "       2. Walk to the back door and open it"
echo "       3. Leave the house immediately"
echo "       4. Go to neighbor's house"
echo "       5. Call gas company from neighbor's phone"
echo ""
echo "  3. Bold Warnings (at least 2):"
echo "     → Include text with 'DO NOT' or 'NEVER' or 'WARNING'"
echo "     → Make these warnings BOLD"
echo "     → Example: 'DO NOT use your cell phone inside'"
echo ""
echo "  4. Emergency Contact Section:"
echo "     → Add heading like 'Emergency Contacts' or 'Who To Call'"
echo "     → Include at least 2 contacts with phone numbers"
echo "     → Example: 'Gas Company: 1-800-555-1234'"
echo "     → Example: 'Maria (daughter): 555-123-4567'"
echo ""
echo "  5. Keep it concise (one page, under 800 words)"
echo ""
echo "  6. Save the document (Ctrl+S)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"