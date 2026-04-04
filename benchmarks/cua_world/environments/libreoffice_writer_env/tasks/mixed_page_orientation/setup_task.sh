#!/bin/bash
# setup_task.sh for mixed_page_orientation task
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Mixed Page Orientation Task ==="

# Create documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
chown ga:ga /tmp/task_start_time.txt

# Create the BCP draft with wide tables in a single portrait document
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# --- Page 1: Cover & Narrative (Portrait) ---
title = doc.add_paragraph("Meridian Financial Services, LLC")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
title.runs[0].bold = True
title.runs[0].font.size = Pt(18)

subtitle = doc.add_paragraph("Business Continuity Plan v2.4")
subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_paragraph("")
doc.add_heading("Executive Summary", level=1)
doc.add_paragraph(
    "This Business Continuity Plan (BCP) documents the strategies and procedures "
    "required for Meridian Financial Services to maintain critical business functions "
    "during a disruption. The plan covers all operational facilities and critical "
    "IT infrastructure."
)
doc.add_paragraph(
    "The primary objective is to minimize financial loss to the firm and ensure "
    "continued service to our clients. This document is maintained by the Risk "
    "Management committee and updated quarterly."
)
doc.add_page_break()

# --- Page 2: Business Impact Analysis (Needs Landscape) ---
doc.add_heading("Section 3: Business Impact Analysis", level=1)
doc.add_paragraph(
    "The following table details the potential impact of a disruption to business "
    "operations over time. (Note: This table is too wide for standard margins)."
)

# Wide table (9 columns)
table = doc.add_table(rows=1, cols=9)
table.style = 'Table Grid'
hdr_cells = table.rows[0].cells
headers = ["Function", "Dept", "RTO (hrs)", "RPO (hrs)", "MTD (hrs)", "Fin Impact ($)", "Ops Impact", "Priority", "Dependencies"]
for i, h in enumerate(headers):
    hdr_cells[i].text = h

# Add dummy data
data = [
    ["Trading Desk", "Inv", "4", "0", "8", "500,000/hr", "Critical", "High", "Bloomberg, Network"],
    ["Client Portal", "IT", "2", "1", "4", "50,000/hr", "High", "High", "Web Server, DB"],
    ["Payroll", "HR", "72", "24", "120", "Low", "Medium", "Med", "ADP Link"],
    ["Compliance", "Legal", "24", "24", "48", "Regulatory", "High", "High", "Email Archive"],
    ["Cust Service", "Ops", "8", "4", "24", "Reputation", "High", "Med", "VoIP System"],
]
for row_data in data:
    row_cells = table.add_row().cells
    for i, item in enumerate(row_data):
        row_cells[i].text = item

doc.add_paragraph("")
doc.add_page_break()

# --- Page 3: Recovery Strategies (Portrait) ---
doc.add_heading("Section 4: Recovery Strategies", level=1)
doc.add_paragraph(
    "Recovery strategies are based on the BIA results. Critical functions "
    "require hot-site recovery capabilities, while non-critical functions "
    "may utilize work-from-home (WFH) procedures."
)
doc.add_paragraph(
    "In the event of a facility loss, the Crisis Management Team (CMT) will "
    "convene at the secondary site or via conference bridge to authorize "
    "departmental recovery plans."
)
doc.add_page_break()

# --- Page 4: Emergency Contact Matrix (Needs Landscape) ---
doc.add_heading("Appendix A: Emergency Contact Matrix", level=1)
doc.add_paragraph("Confidential personnel contact information.")

# Wide table (8 columns)
table2 = doc.add_table(rows=1, cols=8)
table2.style = 'Table Grid'
hdr_cells2 = table2.rows[0].cells
headers2 = ["Name", "Role", "Dept", "Mobile", "Home", "Work Email", "Personal Email", "Alt Contact"]
for i, h in enumerate(headers2):
    hdr_cells2[i].text = h

contacts = [
    ["John Smith", "CMT Lead", "Exec", "555-0101", "555-0102", "jsmith@meridian.com", "jsmith@gmail.com", "Spouse"],
    ["Jane Doe", "IT Lead", "IT", "555-0103", "555-0104", "jdoe@meridian.com", "jdoe@yahoo.com", "Parent"],
    ["Bob Jones", "Ops Lead", "Ops", "555-0105", "555-0106", "bjones@meridian.com", "bjones@outlook.com", "Neighbor"],
]
for row_data in contacts:
    row_cells2 = table2.add_row().cells
    for i, item in enumerate(row_data):
        row_cells2[i].text = item

doc.save("/home/ga/Documents/bcp_draft.docx")
print("Created BCP draft document")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/bcp_draft.docx
chmod 666 /home/ga/Documents/bcp_draft.docx

# Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/bcp_draft.docx > /tmp/writer.log 2>&1 &"

# Wait for Writer window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "bcp_draft" 30

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="