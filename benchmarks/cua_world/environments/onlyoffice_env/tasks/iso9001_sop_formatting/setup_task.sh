#!/bin/bash
set -e
echo "=== Setting up ISO 9001 SOP Document Formatting Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Clean up any existing instances
killall -9 onlyoffice-desktopeditors 2>/dev/null || true
sleep 1

# Create the target directory
su - ga -c "mkdir -p /home/ga/Documents/TextDocuments"

# Generate the draft document using python-docx to ensure proper starting state
cat > /tmp/create_draft_sop.py << 'EOF'
from docx import Document
import os

doc = Document()
doc.add_paragraph("SOP-08: Control of Nonconforming Outputs")
doc.add_paragraph("1. Purpose")
doc.add_paragraph("The purpose of this procedure is to define the requirements for identifying, documenting, evaluating, segregating, and disposing of nonconforming outputs to prevent their unintended use or delivery.")
doc.add_paragraph("2. Scope")
doc.add_paragraph("This procedure applies to all raw materials, components, sub-assemblies, and finished medical devices manufactured at the facility.")
doc.add_paragraph("3. Procedure")
doc.add_paragraph("Any employee who discovers a potential nonconformance must immediately segregate the item and notify the Quality Assurance department. The QA Manager will initiate a Nonconformance Report (NCR) within 24 hours.")
doc.add_paragraph("WARNING: Do not release any nonconforming product to the next stage of production or to the customer without documented authorization from the Material Review Board (MRB).")
doc.add_paragraph("4. Revision History")
doc.add_paragraph("Rev, Date, Author, Description")
doc.add_paragraph("A, 2023-01-15, J. Smith, Initial Release")
doc.add_paragraph("B, 2023-06-20, M. Doe, Updated NCR timeline")
doc.add_paragraph("C, 2024-02-10, A. Johnson, Added MRB authorization requirement")

output_path = "/home/ga/Documents/TextDocuments/draft_QA_SOP_08.docx"
doc.save(output_path)
os.system(f"chown ga:ga {output_path}")
EOF

# Execute the python script
python3 /tmp/create_draft_sop.py

# Launch ONLYOFFICE with the draft document
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors /home/ga/Documents/TextDocuments/draft_QA_SOP_08.docx > /tmp/onlyoffice.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ONLYOFFICE window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE"; then
        break
    fi
    sleep 1
done

# Maximize and focus the ONLYOFFICE window to ensure visibility
DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="