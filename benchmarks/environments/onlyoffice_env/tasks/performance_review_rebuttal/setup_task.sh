#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Performance Review Rebuttal Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial rebuttal document
DOC_PATH="$WORKSPACE_DIR/Performance_Review_Rebuttal.docx"

cat > /tmp/create_rebuttal_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt
import sys

doc = Document()

# Add title
title_para = doc.add_paragraph()
title_run = title_para.add_run("PERFORMANCE REVIEW REBUTTAL")
title_run.bold = True
title_run.font.size = Pt(16)

doc.add_paragraph("")

# Add header information
doc.add_paragraph("Employee Name: Jordan Martinez")
doc.add_paragraph("Employee ID: E-4782")
doc.add_paragraph("Review Period: Q3-Q4 2024 (July 1 - December 31, 2024)")
doc.add_paragraph("Date of Submission: December 15, 2024")
doc.add_paragraph("Reviewer: Sarah Thompson, Engineering Manager")

doc.add_paragraph("")

# Add opening statement
doc.add_paragraph("I am writing to formally respond to the performance review dated December 10, 2024. While I appreciate the feedback provided, I must respectfully dispute two specific criticisms that do not accurately reflect my performance during the review period.")

doc.add_paragraph("")
doc.add_paragraph("")

# Add placeholders for the two criticism sections
doc.add_paragraph("[Section 1: Address the meeting attendance criticism here]")
doc.add_paragraph("")
doc.add_paragraph("[Create a table showing your actual meeting attendance with dates]")
doc.add_paragraph("")
doc.add_paragraph("")

doc.add_paragraph("[Section 2: Address the project deadline criticism here]")
doc.add_paragraph("")
doc.add_paragraph("")

doc.add_paragraph("[Add your professional closing statement here]")

doc.save(sys.argv[1])
print(f"Document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_rebuttal_doc.py
python3 /tmp/create_rebuttal_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_rebuttal_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_rebuttal_task.log || true
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

echo "=== Performance Review Rebuttal Task Setup Complete ==="
echo "📝 Instructions:"
echo ""
echo "You received a performance review with two inaccurate criticisms:"
echo ""
echo "CRITICISM 1: 'Employee rarely participated in team meetings"
echo "             (attended less than 50% of weekly standups Q3-Q4)'"
echo ""
echo "CRITICISM 2: 'Missed deadline for Vendor Integration Project"
echo "             by 2 weeks without communication'"
echo ""
echo "Complete the rebuttal document by:"
echo ""
echo "1. Replace [Section 1] placeholder with a section addressing the"
echo "   meeting attendance criticism. Use BOLD formatting for section headers."
echo "   Example: 'Response to Criticism #1: Meeting Attendance'"
echo ""
echo "2. Create a TABLE showing your actual meeting attendance (at least 8 rows)"
echo "   with columns: Date | Meeting Type | Attended"
echo "   Example entries:"
echo "   - July 5, 2024 | Weekly Standup | Yes"
echo "   - July 12, 2024 | Weekly Standup | Yes"
echo "   - etc."
echo ""
echo "3. Replace [Section 2] placeholder with a section addressing the"
echo "   project deadline criticism. Use BOLD formatting for section header."
echo "   Example: 'Response to Criticism #2: Vendor Integration Project Timeline'"
echo ""
echo "4. Replace the closing placeholder with a professional closing statement"
echo "   (e.g., 'I respectfully request that this rebuttal be included...')"
echo ""
echo "5. Save the document (Ctrl+S)"
echo ""
echo "Expected: Professional document with proper structure, evidence table,"
echo "         bold formatting, and 300+ words total."