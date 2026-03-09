#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Resume ATS Remediation Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Generate the "bad" resume using python-docx
# We use a python script to ensure the internal structure matches the specific "bad" state
# (Content in Header, Spaces for alignment)
echo "Generating resume_draft.docx..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()
section = doc.sections[0]
section.left_margin = Inches(1.0)
section.right_margin = Inches(1.0)

# 1. Put Contact Info in Header (The "Mistake")
# ATS often skips headers, so this is a common real-world fix
header = section.header
p = header.paragraphs[0]
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run("JORDAN LEE\n")
run.bold = True
run.font.size = Pt(16)
p.add_run("jordan.lee@example.com | (555) 019-2834 | LinkedIn: /in/jordanlee")

# 2. Body Content
# Experience Section - Plain text heading (The "Mistake")
h = doc.add_paragraph("EXPERIENCE")
h.runs[0].bold = True 
# Note: Not using Heading style, just bold

# Job 1
p = doc.add_paragraph()
run = p.add_run("Senior Marketing Manager")
run.bold = True
# 25 spaces to simulate bad alignment using spacebar
p.add_run("                         June 2020 – Present")
doc.add_paragraph("TechFlow Solutions, Austin, TX")
doc.add_paragraph("• Led a team of 5 marketing specialists to drive 40% YoY growth.")
doc.add_paragraph("• Managed a $2M annual advertising budget across Google and LinkedIn.")
doc.add_paragraph("")

# Job 2
p = doc.add_paragraph()
run = p.add_run("Marketing Specialist")
run.bold = True
p.add_run("                              Jan 2018 – May 2020")
doc.add_paragraph("Rivera Inc, Austin, TX")
doc.add_paragraph("• Increased organic traffic by 150% through SEO initiatives.")
doc.add_paragraph("• Coordinated 3 major product launches.")
doc.add_paragraph("")

# Education Section
h = doc.add_paragraph("EDUCATION")
h.runs[0].bold = True

p = doc.add_paragraph()
run = p.add_run("B.A. Business Administration")
run.bold = True
p.add_run("               May 2017")
doc.add_paragraph("University of Texas at Austin")
doc.add_paragraph("")

# Skills Section
h = doc.add_paragraph("SKILLS")
h.runs[0].bold = True
doc.add_paragraph("SEO, Google Analytics, CRM, Content Strategy, Python, SQL")

doc.save('/home/ga/Documents/resume_draft.docx')
PYEOF

# Set ownership
chown ga:ga /home/ga/Documents/resume_draft.docx

# Start LibreOffice Writer
echo "Starting LibreOffice Writer..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/resume_draft.docx > /tmp/writer.log 2>&1 &"
fi

# Wait for window
if wait_for_window "LibreOffice Writer" 60; then
    echo "Writer window detected."
else
    # Fallback check for document title
    wait_for_window "resume_draft" 30 || echo "WARNING: Window not found, proceeding anyway..."
fi

# Get Window ID
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="