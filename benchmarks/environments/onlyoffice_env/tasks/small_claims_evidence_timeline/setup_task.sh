#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Small Claims Evidence Timeline Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document with unsorted evidence
DOC_PATH="$WORKSPACE_DIR/evidence_raw.docx"

cat > /tmp/create_evidence_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Add title
title = doc.add_paragraph("SMALL CLAIMS COURT - EVIDENCE ORGANIZATION TASK")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in title.runs:
    run.font.size = Pt(16)
    run.font.bold = True

doc.add_paragraph("")

# Add instructions
instructions = doc.add_paragraph("INSTRUCTIONS:")
instructions.runs[0].font.bold = True
instructions.runs[0].font.size = Pt(12)

doc.add_paragraph("You are helping Maria prepare evidence for small claims court against contractor Luis Martinez.")
doc.add_paragraph("Case: Silva v. Martinez Home Repair Dispute")
doc.add_paragraph("Case Number: 2024-SC-8847")
doc.add_paragraph("")

doc.add_paragraph("TASK: Create a new document titled 'SmallClaims_Evidence_Timeline.docx' with:")
doc.add_paragraph("  1. Document header with case title and number", style='List Bullet')
doc.add_paragraph("  2. A chronological evidence table with 3 columns:", style='List Bullet')
doc.add_paragraph("     - Date (MM/DD/YYYY format)", style='List Bullet 2')
doc.add_paragraph("     - Event Description", style='List Bullet 2')
doc.add_paragraph("     - Evidence Reference", style='List Bullet 2')
doc.add_paragraph("  3. Summary section with financial totals", style='List Bullet')

doc.add_paragraph("")
doc.add_paragraph("=" * 80)
doc.add_paragraph("")

# Add unsorted evidence (deliberately out of order)
evidence_title = doc.add_paragraph("RAW EVIDENCE ENTRIES (UNSORTED):")
evidence_title.runs[0].font.bold = True
evidence_title.runs[0].font.size = Pt(12)
evidence_title.runs[0].font.color.rgb = RGBColor(128, 0, 0)

doc.add_paragraph("")

# Evidence in random order
evidence_entries = [
    "May 2, 2024 - Final text attempt to contractor, no response received (Screenshot C)",
    "March 18, 2024 - First payment made via Zelle transfer, amount $3,500 (Receipt #ZL-4829)",
    "April 15, 2024 - Contractor sent text message: 'Still waiting on parts' (Screenshot B)",
    "March 15, 2024 - Initial contract signed for bathroom repair, agreed price $3,500",
    "May 10, 2024 - Hired new contractor to complete work, total cost $2,800 (Invoice #4422)",
    "March 29, 2024 - Work stopped, contractor claims 'supply delays' via phone call",
    "April 3, 2024 - Contractor sent text message: 'Will be back next week' (Screenshot A)",
    "March 22, 2024 - Contractor began demolition work (Photo evidence: demolished shower tile)"
]

for entry in evidence_entries:
    p = doc.add_paragraph(f"• {entry}")
    p.paragraph_format.left_indent = Pt(20)

doc.add_paragraph("")
doc.add_paragraph("=" * 80)
doc.add_paragraph("")

# Add reminder
reminder = doc.add_paragraph("REMEMBER:")
reminder.runs[0].font.bold = True
doc.add_paragraph("• Sort entries chronologically (earliest to latest)")
doc.add_paragraph("• Format all dates as MM/DD/YYYY")
doc.add_paragraph("• Include evidence references (Photo, Receipt, Screenshot, Invoice)")
doc.add_paragraph("• Add summary showing: Total Paid ($3,500), Cost to Complete ($2,800), Amount Claimed ($3,500)")
doc.add_paragraph("• Save as 'SmallClaims_Evidence_Timeline.docx'")

doc.save(sys.argv[1])
print(f"Evidence document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_evidence_doc.py
python3 /tmp/create_evidence_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Evidence document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_evidence_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_evidence_task.log || true
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

echo "=== Small Claims Evidence Timeline Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  Case: Silva v. Martinez - Incomplete home repair dispute"
echo "  Goal: Create chronologically organized evidence timeline"
echo ""
echo "📋 Requirements:"
echo "  1. Create new document: SmallClaims_Evidence_Timeline.docx"
echo "  2. Add header with case information"
echo "  3. Create 3-column table with 8 evidence entries"
echo "  4. Sort entries chronologically (March 15 → May 10)"
echo "  5. Format dates as MM/DD/YYYY"
echo "  6. Include evidence references"
echo "  7. Add summary section with amounts"
echo ""
echo "💡 The raw evidence document is currently open for reference"