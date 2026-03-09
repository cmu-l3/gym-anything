#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Tenant Complaint Letter Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank document for the complaint letter
DOC_PATH="$WORKSPACE_DIR/complaint_letter.docx"

cat > /tmp/create_complaint_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

# Create a blank document
doc = Document()

# Add a single empty paragraph to initialize the document
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Blank complaint letter document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_complaint_doc.py
python3 /tmp/create_complaint_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Blank document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_complaint_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_complaint_task.log || true
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

echo "=== Tenant Complaint Letter Task Setup Complete ==="
echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║                    TENANT COMPLAINT LETTER TASK                        ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 SCENARIO:"
echo "   Your apartment heating has been broken for 2 weeks during January."
echo "   Your landlord has ignored multiple contact attempts (calls, texts, email)."
echo "   You need to write a formal complaint letter to create a paper trail"
echo "   before escalating to legal action or the housing authority."
echo ""
echo "✍️  REQUIRED CONTENT:"
echo ""
echo "   1. YOUR ADDRESS (top right or left):"
echo "      427 Oak Street, Apt 3B"
echo "      Portland, OR 97214"
echo ""
echo "   2. DATE: Any date in January 2024"
echo ""
echo "   3. LANDLORD ADDRESS (left-aligned):"
echo "      Mr. Robert Chen"
echo "      1550 Property Management LLC"
echo "      890 Commercial Ave"
echo "      Portland, OR 97201"
echo ""
echo "   4. SALUTATION: Dear Mr. Chen,"
echo ""
echo "   5. OPENING PARAGRAPH:"
echo "      - State purpose: formal written notice (make 'formal written notice' BOLD)"
echo "      - Mention heating system failure"
echo ""
echo "   6. TIMELINE TABLE (3 columns, 4+ rows):"
echo "      Headers: Date | Contact Method | Response"
echo "      Example rows:"
echo "        Jan 8  | Phone call    | No answer"
echo "        Jan 10 | Text message  | Read, no reply"
echo "        Jan 12 | Email         | No response"
echo "        Jan 15 | In-person     | No response"
echo ""
echo "   7. IMPACT STATEMENT:"
echo "      - Health concerns, work disruption"
echo "      - Mention tenant rights (Oregon Residential Landlord-Tenant Act)"
echo ""
echo "   8. DEMAND FOR ACTION:"
echo "      - Request: repair or replacement of heating system"
echo "      - Deadline: within 72 hours (make BOLD and UNDERLINED)"
echo "      - Mention next steps: housing authority complaint"
echo ""
echo "   9. PROFESSIONAL CLOSING:"
echo "      - Sincerely, or Respectfully,"
echo "      - Your name: Jessica Martinez"
echo "      - Phone: (503) 555-0147"
echo ""
echo "📝 FORMATTING REQUIREMENTS:"
echo "   • Title at top: 'Formal Complaint - Heating System Failure'"
echo "     (should be BOLD and 18pt font)"
echo "   • At least 4 distinct paragraphs"
echo "   • Table with visible borders"
echo "   • Professional tone throughout"
echo ""
echo "💾 When finished, save the document (Ctrl+S)"
echo ""
echo "Document path: $DOC_PATH"
echo "════════════════════════════════════════════════════════════════════════"