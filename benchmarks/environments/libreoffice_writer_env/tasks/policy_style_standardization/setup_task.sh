#!/bin/bash
set -e

echo "=== Setting up Policy Style Standardization Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Record task start time
date +%s > /tmp/task_start_time.txt

# Generate the messy draft document using python-docx
# We inject "bad" direct formatting that the agent must clear
cat << 'PYEOF' | python3
import os
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Add a messy title (manual formatting, no style)
title = doc.add_paragraph("Company Remote Work Policy (DRAFT)")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in title.runs:
    run.font.name = "Comic Sans MS"
    run.font.size = Pt(20)
    run.font.color.rgb = RGBColor(255, 0, 0)  # Red
    run.bold = True

doc.add_paragraph("")

# Section 1: Objective (Manual bold, wrong font, not Heading 1)
p = doc.add_paragraph("1. Objective")
run = p.runs[0]
run.font.name = "Courier New"
run.font.size = Pt(14)
run.bold = True
run.font.color.rgb = RGBColor(0, 100, 0) # Green

# Body text (Messy mix of fonts and highlights)
p = doc.add_paragraph(
    "This policy outlines the guidelines for employees who work from home. "
    "It is vital that we maintain productivity and security."
)
# Make it messy
p.runs[0].font.name = "Comic Sans MS"
p.runs[0].font.size = Pt(12)

# Section 2: Scope
p = doc.add_paragraph("2. Scope")
run = p.runs[0]
run.font.name = "Times New Roman"
run.font.size = Pt(14)
run.bold = True
run.underline = True

p = doc.add_paragraph(
    "This policy applies to all full-time employees eligible for remote work. "
    "Exceptions may be granted by HR."
)
p.runs[0].font.name = "Liberation Mono"

# Section 3: Equipment
p = doc.add_paragraph("3. Equipment")
run = p.runs[0]
run.font.name = "Arial" # Correct font but direct formatting
run.font.size = Pt(18) # Wrong size
run.bold = True

p = doc.add_paragraph(
    "The company will provide a laptop and VPN access. Employees are responsible "
    "for their own internet connection."
)
# Random color in body
p.runs[0].font.color.rgb = RGBColor(100, 0, 100)

# Section 4: Security
p = doc.add_paragraph("4. Security")
run = p.runs[0]
run.bold = True

p = doc.add_paragraph(
    "Use strong passwords. Do not use public Wi-Fi without VPN. "
    "Lock your screen when away."
)
p.alignment = WD_ALIGN_PARAGRAPH.RIGHT # Wrong alignment

doc.save("/home/ga/Documents/remote_work_policy_draft.docx")
print("Messy draft created.")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/remote_work_policy_draft.docx

# Launch LibreOffice Writer with the messy file
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/remote_work_policy_draft.docx > /tmp/writer.log 2>&1 &"

# Wait for Writer to appear
wait_for_window "LibreOffice Writer" 60 || wait_for_window "remote_work_policy" 30

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="