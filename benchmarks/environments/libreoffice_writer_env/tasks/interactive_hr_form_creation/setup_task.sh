#!/bin/bash
set -euo pipefail

echo "=== Setting up Interactive HR Form Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the draft ODT document using python (odfpy)
# We create a simple document with text labels where controls should go
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P
from odf.style import Style, TextProperties, ParagraphProperties

doc = OpenDocumentText()

# Create a title style
h1_style = Style(name="Heading 1", family="paragraph")
h1_style.addElement(TextProperties(attributes={'fontsize':"18pt", 'fontweight':"bold"}))
h1_style.addElement(ParagraphProperties(attributes={'textalign':"center"}))
doc.automaticstyles.addElement(h1_style)

# Create label style
label_style = Style(name="Label", family="paragraph")
label_style.addElement(TextProperties(attributes={'fontsize':"12pt", 'fontweight':"bold"}))
doc.automaticstyles.addElement(label_style)

# Title
doc.text.addElement(P(text="NEW EMPLOYEE ONBOARDING FORM", stylename=h1_style))
doc.text.addElement(P(text=""))

# Personal Info Section
doc.text.addElement(P(text="PERSONAL INFORMATION", stylename=label_style))
doc.text.addElement(P(text="Full Name:   [ Insert Text Box Here ]"))
doc.text.addElement(P(text="Job Title:   [ Insert Text Box Here ]"))
doc.text.addElement(P(text=""))

# Start Date Section
doc.text.addElement(P(text="START DETAILS", stylename=label_style))
doc.text.addElement(P(text="Start Date:  [ Insert Date Field Here ]"))
doc.text.addElement(P(text=""))

# Status Section
doc.text.addElement(P(text="EMPLOYMENT STATUS", stylename=label_style))
doc.text.addElement(P(text="(Select one)"))
doc.text.addElement(P(text="      Full-Time   [ Insert Radio Button Here ]"))
doc.text.addElement(P(text="      Part-Time   [ Insert Radio Button Here ]"))
doc.text.addElement(P(text=""))

# IT Section
doc.text.addElement(P(text="IT PROVISIONING", stylename=label_style))
doc.text.addElement(P(text="      Company Laptop Required?   [ Insert Check Box Here ]"))

doc.save("/home/ga/Documents/onboarding_draft.odt")
print("Draft ODT created.")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/onboarding_draft.odt

# Launch LibreOffice Writer with the draft
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/onboarding_draft.odt > /tmp/writer_task.log 2>&1 &"

# Wait for Writer to start
wait_for_window "LibreOffice Writer" 60 || wait_for_window "onboarding_draft" 30

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss "Tip of the Day" if it appears
    sleep 2
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="