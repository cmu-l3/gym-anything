#!/bin/bash
set -e

echo "=== Setting up BCP Draft Watermark Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Create the source BCP document using python-docx
# This creates a realistic multi-page document based on FEMA COOP templates
echo "Generating BCP source document..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Title Page content
title = doc.add_paragraph("CONTINUITY OF OPERATIONS (COOP) PLAN")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in title.runs:
    run.bold = True
    run.font.size = Pt(24)

doc.add_paragraph("\n" * 4)

subtitle = doc.add_paragraph("Meridian Financial Group")
subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in subtitle.runs:
    run.font.size = Pt(18)

doc.add_paragraph("\n" * 2)

date_para = doc.add_paragraph("February 2024")
date_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_page_break()

# Table of Contents placeholder
doc.add_paragraph("TABLE OF CONTENTS").style = 'Heading 1'
doc.add_paragraph("I. PURPOSE AND SCOPE................................................................ 3")
doc.add_paragraph("II. CONCEPT OF OPERATIONS...................................................... 4")
doc.add_paragraph("III. ESSENTIAL FUNCTIONS........................................................... 6")
doc.add_paragraph("IV. ORDER OF SUCCESSION.......................................................... 8")
doc.add_page_break()

# Section I
doc.add_paragraph("I. PURPOSE AND SCOPE").style = 'Heading 1'
doc.add_paragraph(
    "The purpose of this Continuity of Operations (COOP) plan is to ensure the "
    "continued performance of Meridian Financial Group's essential functions during "
    "a wide range of potential emergencies. This plan provides the framework for "
    "restoring critical business processes and maintaining financial services for "
    "our clients in the event of a disruption."
)
doc.add_paragraph(
    "This plan applies to all Meridian Financial Group facilities and personnel. "
    "It covers all hazards, including natural disasters, technical failures, and "
    "human-caused threats."
)
doc.add_paragraph("\n")

# Section II
doc.add_paragraph("II. CONCEPT OF OPERATIONS").style = 'Heading 1'
doc.add_paragraph(
    "Upon activation of the COOP plan, the Crisis Management Team (CMT) will "
    "assume responsibility for all emergency operations. The CMT will determine "
    "whether to relocate to the alternate facility at 4500 Tech Park Drive."
)
doc.add_paragraph(
    "Phase 1: Activation and Relocation (0-12 hours)"
)
doc.add_paragraph(
    "Phase 2: Alternate Facility Operations (12 hours - 30 days)"
)
doc.add_paragraph(
    "Phase 3: Reconstitution (Termination of COOP)"
)
doc.add_page_break()

# Section III
doc.add_paragraph("III. ESSENTIAL FUNCTIONS").style = 'Heading 1'
doc.add_paragraph(
    "The following functions have been identified as critical to the mission "
    "of Meridian Financial Group and must be restored within the stated Recovery "
    "Time Objectives (RTO):"
)
table = doc.add_table(rows=4, cols=3)
table.style = 'Table Grid'
hdr_cells = table.rows[0].cells
hdr_cells[0].text = 'Function'
hdr_cells[1].text = 'Priority'
hdr_cells[2].text = 'RTO'

row1 = table.rows[1].cells
row1[0].text = 'Client Trading Execution'
row1[1].text = 'Critical'
row1[2].text = '4 hours'

row2 = table.rows[2].cells
row2[0].text = 'Regulatory Reporting'
row2[1].text = 'High'
row2[2].text = '24 hours'

row3 = table.rows[3].cells
row3[0].text = 'Payroll Processing'
row3[1].text = 'Medium'
row3[2].text = '72 hours'

doc.add_paragraph("\n")

# Section IV
doc.add_paragraph("IV. ORDER OF SUCCESSION").style = 'Heading 1'
doc.add_paragraph(
    "In the event that the Chief Executive Officer is unable to perform their duties, "
    "authority shall pass to the following officials in the order listed:"
)
doc.add_paragraph("1. Chief Operating Officer", style='List Number')
doc.add_paragraph("2. Chief Financial Officer", style='List Number')
doc.add_paragraph("3. General Counsel", style='List Number')

doc.save("/home/ga/Documents/bcp_plan.docx")
print("BCP document created successfully.")
PYEOF

# Set proper permissions
chown ga:ga /home/ga/Documents/bcp_plan.docx
chmod 666 /home/ga/Documents/bcp_plan.docx

# Calculate initial hash of the source file
md5sum /home/ga/Documents/bcp_plan.docx | awk '{print $1}' > /tmp/original_hash.txt

# Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/bcp_plan.docx > /tmp/writer_launch.log 2>&1 &"

# Wait for process
wait_for_process "soffice" 20

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "bcp_plan" 30

# Maximize and focus
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Focusing window $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss potential "What's New" or recovery dialogs
    sleep 2
    safe_xdotool ga :1 key Escape
    sleep 0.5
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="