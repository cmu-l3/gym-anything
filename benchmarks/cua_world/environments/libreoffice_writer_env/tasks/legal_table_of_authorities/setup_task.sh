#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Legal Table of Authorities Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Record task start time
date +%s > /tmp/task_start_time.txt
chown ga:ga /tmp/task_start_time.txt

# Create the appellate brief draft using python-docx
# We intentionally create a multi-page document to ensure page numbers in TOA are interesting
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK

doc = Document()

# --- Page 1: Title Page ---
title = doc.add_paragraph("IN THE\nUNITED STATES COURT OF APPEALS\nFOR THE TWELFTH CIRCUIT")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in title.runs:
    run.bold = True
    run.font.size = Pt(14)

doc.add_paragraph("\n" * 5)

caption = doc.add_paragraph("CASE NO. 24-1109\n\nSMITH MANUFACTURING CO.,\nAppellant,\n\nv.\n\nJONES DISTRIBUTION, INC.,\nAppellee.")
caption.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in caption.runs:
    run.font.size = Pt(12)

doc.add_paragraph("\n" * 8)

footer = doc.add_paragraph("ON APPEAL FROM THE DISTRICT COURT\nBRIEF OF APPELLANT")
footer.alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_break(WD_BREAK.PAGE)

# --- Page 2: Placeholder for TOA ---
toa_header = doc.add_paragraph("TABLE OF AUTHORITIES")
toa_header.alignment = WD_ALIGN_PARAGRAPH.CENTER
toa_header.style = "Heading 1"

doc.add_paragraph("\n[Insert Table of Authorities Here]\n")

doc.add_break(WD_BREAK.PAGE)

# --- Page 3: Argument Section ---
doc.add_paragraph("ARGUMENT").alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_paragraph("I. THE DISTRICT COURT ERRED IN CALCULATING DAMAGES.")

p1 = doc.add_paragraph(
    "The fundamental principle of contract damages, as established in "
    "Hadley v. Baxendale, 9 Exch. 341 (1854), is that damages are limited to those "
    "reasonably foreseeable by the parties at the time of contracting. "
    "In this case, the consequential damages claimed by Jones Distribution were "
    "neither communicated nor foreseeable."
)

p2 = doc.add_paragraph(
    "Furthermore, under the Uniform Commercial Code, specifically U.C.C. § 2-715, "
    "consequential damages resulting from the seller's breach include any loss "
    "resulting from general or particular requirements and needs of which the "
    "seller at the time of contracting had reason to know."
)

doc.add_paragraph("\n")

p3 = doc.add_paragraph(
    "Unlike the hairy hand case of Hawkins v. McGee, 84 N.H. 114 (1929), where "
    "expectation damages were clearly defined by the difference between the "
    "value of the guaranteed good hand and the hand as delivered, the present "
    "case involves speculative lost profits."
)

doc.add_break(WD_BREAK.PAGE)

# --- Page 4: Jurisdiction ---
doc.add_paragraph("II. JURISDICTIONAL STATEMENT").alignment = WD_ALIGN_PARAGRAPH.CENTER

p4 = doc.add_paragraph(
    "This Court has jurisdiction under 28 U.S.C. § 1332 because the parties "
    "are citizens of different states and the amount in controversy exceeds "
    "$75,000. The Plaintiff, Smith Manufacturing, is incorporated in Delaware."
)

p5 = doc.add_paragraph(
    "Returning to the principle of Hadley v. Baxendale, the special circumstances "
    "were not known to the defendant. Similarly, the strictures of U.C.C. § 2-715 "
    "require actual or constructive knowledge."
)

doc.save("/home/ga/Documents/appellate_brief_draft.docx")
print("Created appellate brief draft")
PYEOF

chown ga:ga /home/ga/Documents/appellate_brief_draft.docx
chmod 666 /home/ga/Documents/appellate_brief_draft.docx

# Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/appellate_brief_draft.docx > /tmp/writer_task.log 2>&1 &"

# Wait for process
if ! wait_for_process "soffice" 20; then
    echo "ERROR: LibreOffice failed to start"
    exit 1
fi

# Wait for window
if ! wait_for_window "LibreOffice Writer" 60; then
    wait_for_window "appellate_brief" 30 || true
fi

# Focus window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 1
    # Dismiss any initial dialogs
    safe_xdotool ga :1 key Escape
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="