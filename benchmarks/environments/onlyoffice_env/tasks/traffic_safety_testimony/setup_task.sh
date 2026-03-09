#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Traffic Safety Testimony Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank document for the testimony
DOC_PATH="$WORKSPACE_DIR/oak_street_testimony.docx"

cat > /tmp/create_testimony_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

# Create a completely blank document
doc = Document()

# Add a single empty paragraph to ensure document is valid
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Blank testimony document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_testimony_doc.py
python3 /tmp/create_testimony_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Blank testimony document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_testimony_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_testimony_task.log || true
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

echo "=== Traffic Safety Testimony Task Setup Complete ==="
echo ""
echo "📝 SCENARIO: You are helping resident Jordan Chen prepare City Council testimony"
echo "   about dangerous speeding on Oak Street. Create a professional testimony document."
echo ""
echo "REQUIRED DOCUMENT STRUCTURE:"
echo ""
echo "1. HEADER:"
echo "   - Speaker: Jordan Chen, Oak Street Resident (name should be BOLD)"
echo "   - Meeting: City Council Public Comment"
echo "   - Date: May 14, 2025"
echo "   - Topic: Request for Traffic Calming on Oak Street"
echo ""
echo "2. OPENING STATEMENT:"
echo "   - Brief intro explaining who you are and why you're speaking"
echo "   - Must include: 'urgent traffic calming measures on Oak Street between Main Avenue and 5th Street'"
echo ""
echo "3. EVIDENCE TABLE (create table with 4 columns):"
echo "   - Columns: Date | Time | Incident Type | Details"
echo "   - Include at least 4 incidents:"
echo "     * 3/15/2025 | 4:30 PM | Near-miss | Child on bicycle nearly hit at Oak & 3rd"
echo "     * 3/28/2025 | Evening | Fatality | Neighbor's cat killed by speeding vehicle"
echo "     * 4/10/2025 | 7:45 AM | Speed observation | Multiple cars at 42-45 mph (limit is 25)"
echo "     * 4/22/2025 | 3:00 PM | Close call | Elderly resident nearly struck checking mailbox"
echo "   - Make header row BOLD"
echo ""
echo "4. COMMUNITY SUPPORT:"
echo "   - State that 23 households signed supporting this request"
echo "   - Make '23 households' BOLD"
echo ""
echo "5. PROPOSED SOLUTIONS (bulleted list with at least 3 items):"
echo "   - Speed bumps at Oak & 2nd and Oak & 4th"
echo "   - Enhanced signage including 'Children at Play' warnings"
echo "   - Speed feedback signs (showing drivers their current speed)"
echo ""
echo "6. CLOSING STATEMENT:"
echo "   - Call to action with 'respectfully urge' and mention '60 days'"
echo "   - Example: 'I respectfully urge the Council to approve a traffic study and"
echo "     implement calming measures on Oak Street within 60 days.'"
echo ""
echo "7. CONTACT INFO:"
echo "   - Email: jordan.chen@email.com"
echo "   - Phone: (555) 234-5678"
echo ""
echo "💾 Save the document when complete (Ctrl+S)"
echo ""