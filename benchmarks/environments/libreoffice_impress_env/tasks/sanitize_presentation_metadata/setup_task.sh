#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Sanitize Metadata Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create the "dirty" presentation with metadata and comments using Python
# We use python3 with odfpy which is installed in the environment
echo "Generating input file with metadata..."
sudo -u ga python3 - << 'EOF'
import os
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P
from odf.office import Annotation
from odf.dc import Creator, Date
from odf.meta import InitialCreator, UserDefined

# Create document
doc = OpenDocumentPresentation()

# 1. Inject Metadata (Author and Custom Property)
# Note: odfpy adds these to meta.xml
doc.meta.addElement(InitialCreator(text="Internal Audit Team"))
doc.meta.addElement(Creator(text="Internal Audit Team"))
doc.meta.addElement(UserDefined(name="Classification", text="Confidential", value_type="string"))

# 2. Add Slide 1
page1 = Page(name="Incident_Summary")
doc.presentation.addElement(page1)

# Title Frame
frame1 = Frame(width="20cm", height="3cm", x="2cm", y="2cm")
page1.addElement(frame1)
tb1 = TextBox()
frame1.addElement(tb1)
tb1.addElement(P(text="Q3 Security Incident Report"))

# Add a Comment (Annotation) to Slide 1
# In ODF, annotations are often children of the office:body or draw:page depending on version
# odfpy allows adding Annotation objects.
ann1 = Annotation()
ann1.addElement(Creator(text="Reviewer 1"))
ann1.addElement(Date(text="2023-10-15T10:00:00"))
ann1.addElement(P(text="This title is too alarming. Please revise."))
# Position details are complex in ODF, but adding to page usually makes it exist in the DOM
page1.addElement(ann1)

# 3. Add Slide 2
page2 = Page(name="Data_Leakage")
doc.presentation.addElement(page2)

# Content Frame
frame2 = Frame(width="20cm", height="10cm", x="2cm", y="5cm")
page2.addElement(frame2)
tb2 = TextBox()
frame2.addElement(tb2)
tb2.addElement(P(text="Root Cause Analysis: Unpatched Server"))

# Add another Comment
ann2 = Annotation()
ann2.addElement(Creator(text="Manager"))
ann2.addElement(P(text="Are we sure we want to disclose this publicly?"))
page2.addElement(ann2)

# Save file
output_path = "/home/ga/Documents/Presentations/incident_report_draft.odp"
doc.save(output_path)
print(f"Created {output_path}")
EOF

# Ensure permissions
sudo chown ga:ga /home/ga/Documents/Presentations/incident_report_draft.odp

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch LibreOffice Impress with the file
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/incident_report_draft.odp > /tmp/impress_task.log 2>&1 &"

# Wait for process
if ! wait_for_process "soffice" 20; then
    echo "ERROR: LibreOffice failed to start"
    exit 1
fi

# Wait for window
if ! wait_for_window "LibreOffice Impress" 60; then
    echo "WARNING: Window detection timed out, continuing anyway..."
fi

# Focus and Maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Try to maximize
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Open Properties and remove 'Internal Audit Team' and 'Classification: Confidential'."
echo "2. Delete comments on slides."
echo "3. Save as incident_report_public.odp"