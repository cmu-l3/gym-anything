#!/bin/bash
set -e
echo "=== Setting up SLA Template Automation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the initial draft ODT document using Python and odfpy
# We use Python to ensure valid ODT structure
cat << 'PYEOF' | python3
import os
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import P, H, Span

doc = OpenDocumentText()

# Create styles
s_header = Style(name="Heading 1", family="paragraph")
s_header.addElement(TextProperties(attributes={'fontsize':"24pt", 'fontweight':"bold"}))
s_header.addElement(ParagraphProperties(attributes={'textalign':"center"}))
doc.automaticstyles.addElement(s_header)

s_body = Style(name="Standard", family="paragraph")
s_body.addElement(TextProperties(attributes={'fontsize':"12pt", 'fontfamily':"Liberation Serif"}))
doc.automaticstyles.addElement(s_body)

s_bold = Style(name="Bold", family="text")
s_bold.addElement(TextProperties(attributes={'fontweight':"bold"}))
doc.automaticstyles.addElement(s_bold)

# Title
h = H(outlinelevel=1, stylename=s_header, text="MASTER SERVICE LEVEL AGREEMENT")
doc.text.addElement(h)

doc.text.addElement(P(text=""))

# Preamble
p1 = P(stylename=s_body)
p1.addText("This Agreement is made and entered into on ")
p1.addText("[DATE]")
p1.addText(" (the \"Effective Date\"), by and between Sentinels CyberSecurity (\"Provider\") and ")
span = Span(stylename=s_bold, text="[CLIENT]")
p1.addElement(span)
p1.addText(" (\"Customer\").")
doc.text.addElement(p1)

doc.text.addElement(P(text=""))

# 1. Services
doc.text.addElement(H(outlinelevel=2, text="1. SERVICE AVAILABILITY"))
p2 = P(stylename=s_body)
p2.addText("Provider shall use commercially reasonable efforts to make the Services available with a Monthly Uptime Percentage of at least ")
p2.addText("[UPTIME]")
p2.addText(" during any monthly billing cycle.")
doc.text.addElement(p2)

doc.text.addElement(P(text=""))

# 2. Service Credits
doc.text.addElement(H(outlinelevel=2, text="2. SERVICE CREDITS"))
p3 = P(stylename=s_body)
p3.addText("In the event Provider does not meet the Monthly Uptime Percentage of ")
p3.addText("[UPTIME]")
p3.addText(", Customer will be eligible to receive a Service Credit of ")
p3.addText("[CREDIT]")
p3.addText(" of the applicable monthly fees.")
doc.text.addElement(p3)

doc.text.addElement(P(text=""))

# 3. Term
doc.text.addElement(H(outlinelevel=2, text="3. TERM AND TERMINATION"))
p4 = P(stylename=s_body)
p4.addText("This Agreement shall commence on ")
p4.addText("[START DATE]")
p4.addText(" and continue until terminated by either party.")
doc.text.addElement(p4)

doc.text.addElement(P(text=""))

# Signatures
doc.text.addElement(H(outlinelevel=2, text="SIGNATURES"))
p5 = P(stylename=s_body)
p5.addText("IN WITNESS WHEREOF, the parties have executed this Agreement as of the date first above written.")
doc.text.addElement(p5)

doc.text.addElement(P(text=""))
doc.text.addElement(P(text="For: Sentinels CyberSecurity"))
doc.text.addElement(P(text="By: ___________________________"))

doc.text.addElement(P(text=""))
doc.text.addElement(P(text="For: [CLIENT NAME]"))
doc.text.addElement(P(text="By: ___________________________"))

# Save file
output_path = "/home/ga/Documents/SLA_Draft_Sentinels.odt"
doc.save(output_path)
print(f"Created {output_path}")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/SLA_Draft_Sentinels.odt
chmod 666 /home/ga/Documents/SLA_Draft_Sentinels.odt

# Launch LibreOffice Writer with the draft
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/SLA_Draft_Sentinels.odt > /tmp/writer_launch.log 2>&1 &"

# Wait for Writer to appear
wait_for_window "LibreOffice Writer" 60 || wait_for_window "SLA_Draft" 30

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    focus_window "$WID"
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="