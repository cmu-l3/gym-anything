#!/bin/bash
set -e
echo "=== Setting up alternating_headers_footers task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Create the source document using python-docx
# We use Python to generate a realistic looking document structure
echo "Generating source document..."
python3 << 'PYSCRIPT'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
import os

doc = Document()

# Set default font to something standard
style = doc.styles['Normal']
font = style.font
font.name = 'Liberation Serif'
font.size = Pt(12)

# --- TITLE PAGE ---
for _ in range(4): doc.add_paragraph('')

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('IND ANNUAL REPORT')
run.bold = True
run.font.size = Pt(20)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('IND Application Number 123456')
run.font.size = Pt(14)

doc.add_paragraph('')

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('MRD-4721')
run.bold = True
run.font.size = Pt(16)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('A Selective CDK4/6 Inhibitor for the Treatment of\nNSCLC with KRAS G12C Mutation')
run.font.size = Pt(12)

doc.add_paragraph('')
doc.add_paragraph('')

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('Submitted by:\nMeridian Therapeutics, Inc.\nCambridge, MA 02142')
run.font.size = Pt(12)

doc.add_paragraph('')
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('Annual Report Period: April 15, 2023 – April 14, 2024')
run.font.size = Pt(11)

# PAGE BREAK
doc.add_page_break()

# --- CONTENT PAGES (Simulating a 5-6 page report) ---
sections = [
    ("1. General Investigational Plan", 
     "MRD-4721 is a novel, orally bioavailable, selective inhibitor of cyclin-dependent kinases 4 and 6. " * 15),
    ("2. Individual Study Information", 
     "Protocol MRD-4721-001 (Phase 1) has completed enrollment. The MTD was determined to be 200mg QD. " * 10),
    ("3. Summary of Clinical Pharmacology", 
     "Pharmacokinetic analyses demonstrate linear PK over the dose range of 25 to 300 mg. " * 12),
    ("4. Summary of Safety Information", 
     "The safety profile remains consistent with the known mechanism of action. Neutropenia was the most common TEAE. " * 15),
    ("5. Manufacturing Changes", 
     "The synthetic route for MRD-4721 drug substance was optimized to improve yield. " * 10),
    ("6. Outstanding Business", 
     "A pre-IND meeting request was submitted on March 15, 2024 to discuss Phase 3 design. " * 8)
]

for title, content in sections:
    doc.add_heading(title, level=1)
    doc.add_paragraph(content)
    doc.add_paragraph("")
    if title.startswith("2.") or title.startswith("4."):
        doc.add_page_break()

doc.save('/home/ga/Documents/ind_annual_report.docx')
PYSCRIPT

# Set proper permissions
chown ga:ga /home/ga/Documents/ind_annual_report.docx

# Record hash of original file to detect if agent overwrites it
md5sum /home/ga/Documents/ind_annual_report.docx > /tmp/original_doc_hash.txt

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 1

# Open the document in LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/ind_annual_report.docx > /tmp/writer.log 2>&1 &"

# Wait for window to appear
wait_for_window "LibreOffice Writer" 60 || wait_for_window "ind_annual_report" 30

# Maximize and focus the window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
fi

# Dismiss any startup dialogs (like "Tip of the Day")
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="