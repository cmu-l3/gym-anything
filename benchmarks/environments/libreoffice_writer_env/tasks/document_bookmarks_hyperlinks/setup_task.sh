#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Document Bookmarks & Hyperlinks Task ==="

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chown ga:ga /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the draft document with realistic content using python-docx
# We use python-docx to generate a clean structure that the agent must modify
python3 << 'PYEOF'
import os
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Title Page info
title = doc.add_paragraph("County of Maplewood\nDepartment of Human Services")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in title.runs:
    run.bold = True
    run.font.size = Pt(16)

subtitle = doc.add_paragraph("Case Management Procedures Manual")
subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in subtitle.runs:
    run.font.size = Pt(24)
    run.bold = True

doc.add_paragraph("\n\nEffective Date: January 2024\nVersion 2.1\n\n").alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_page_break()

# Content Data
chapters = [
    ("Chapter 1: Intake and Assessment Procedures", 
     "Upon receiving a referral, the Case Manager (CM) must initiate contact with the client within 24 hours. "
     "The initial intake interview serves to establish rapport, gather preliminary demographic information, and "
     "assess immediate safety needs. CMs must complete Form DHS-101 (Initial Intake) and upload it to the central database."),
    
    ("Chapter 2: Service Planning and Goal Setting",
     "Service plans are co-created with the client and must be SMART (Specific, Measurable, Achievable, Relevant, Time-bound). "
     "The Individualized Service Plan (ISP) must be signed by both the client and the supervisor within 14 days of intake. "
     "Goals should focus on fostering independence and utilizing community resources."),

    ("Chapter 3: Crisis Intervention Protocols",
     "In the event of a client crisis (e.g., housing loss, medical emergency, psychiatric distress), the CM must follow "
     "the escalation matrix. Immediate threats to life or safety require a call to 911. Secondary responses involve "
     "mobilizing the Crisis Response Team (CRT). All incidents must be documented in an Incident Report within 4 hours."),

    ("Chapter 4: Documentation and Record Keeping",
     "Accurate and timely documentation is a legal and ethical requirement. Case notes must follow the SOAP format "
     "(Subjective, Objective, Assessment, Plan). All client interactions, including phone calls and emails, must be "
     "logged. Files are subject to quarterly audit by the Quality Assurance department."),

    ("Chapter 5: Client Rights and Confidentiality",
     "Clients have the right to privacy, dignity, and self-determination. Information sharing requires a signed "
     "Release of Information (ROI) form, compliant with HIPAA and 42 CFR Part 2 regulations. Breaches of confidentiality "
     "are grounds for immediate disciplinary action."),

    ("Chapter 6: Interagency Coordination and Referrals",
     "Effective case management requires collaboration with external agencies (e.g., Housing Authority, SSA, Behavioral Health). "
     "Referrals should be tracked in the outcome monitoring system. CMs are expected to maintain up-to-date knowledge of "
     "community eligibility requirements."),

    ("Chapter 7: Quality Assurance and Program Evaluation",
     "Program outcomes are measured through client satisfaction surveys and permanency metrics. The QA team conducts "
     "monthly file reviews. CMs falling below 85% compliance on documentation standards will be placed on a Performance "
     "Improvement Plan (PIP)."),

    ("Chapter 8: Staff Training and Professional Development",
     "All case management staff must complete 20 hours of continuing education units (CEUs) annually. Mandatory trainings "
     "include Ethics, Cultural Competency, and Trauma-Informed Care. Tuition reimbursement is available for relevant "
     "graduate coursework.")
]

# Add Chapters
for title, text in chapters:
    # Heading 1 style is crucial for the agent to identify where to put bookmarks
    h = doc.add_heading(title, level=1)
    
    # Add some body text
    p = doc.add_paragraph(text)
    p_format = p.paragraph_format
    p_format.space_after = Pt(12)
    
    # Add a filler paragraph to make document longer
    doc.add_paragraph(
        "Refer to the specific appendices for detailed workflows and contact lists associated with this section. "
        "Standard operating procedures (SOPs) are updated biannually."
    )
    doc.add_page_break()

# Save
output_path = "/home/ga/Documents/case_manual_draft.docx"
doc.save(output_path)
print(f"Created {output_path}")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/case_manual_draft.docx
chmod 666 /home/ga/Documents/case_manual_draft.docx

# Launch LibreOffice Writer with the file
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/case_manual_draft.docx > /tmp/writer_task.log 2>&1 &"

# Wait for Writer to open
if ! wait_for_window "LibreOffice Writer" 60; then
    # Try waiting for the specific filename in title
    wait_for_window "case_manual_draft" 30 || true
fi

# Maximize the window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    echo "Maximizing window $wid"
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="