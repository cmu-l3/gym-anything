#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Custom Icons Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Generate the starting ODP file programmatically using odfpy
# This ensures precise coordinates and object types
echo "Generating starting presentation..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Rect, Ellipse, Frame, TextBox
from odf.style import Style, GraphicProperties, ParagraphProperties, TextProperties
from odf.text import P

doc = OpenDocumentPresentation()

# Define Styles
# Server Body Style (Blue)
server_style = Style(name="ServerBody", family="graphic")
server_style.addElement(GraphicProperties(fill="solid", fillcolor="#2b5797", stroke="none"))
doc.automaticstyles.addElement(server_style)

# Server Light Style (White)
light_style = Style(name="ServerLight", family="graphic")
light_style.addElement(GraphicProperties(fill="solid", fillcolor="#ffffff", stroke="none"))
doc.automaticstyles.addElement(light_style)

# Cloud Style (Gray)
cloud_style = Style(name="CloudPart", family="graphic")
cloud_style.addElement(GraphicProperties(fill="solid", fillcolor="#aaaaaa", stroke="none"))
doc.automaticstyles.addElement(cloud_style)

# --- Slide 1: Server Asset ---
page1 = Page(name="Server Asset")
doc.presentation.addElement(page1)

# Server Body (Rectangle)
rect = Rect(style_name=server_style, x="4cm", y="4cm", width="6cm", height="10cm")
page1.addElement(rect)

# Server Lights (Ellipses) - to be subtracted
light1 = Ellipse(style_name=light_style, x="8cm", y="5cm", width="1cm", height="1cm")
light2 = Ellipse(style_name=light_style, x="8cm", y="7cm", width="1cm", height="1cm")
light3 = Ellipse(style_name=light_style, x="8cm", y="9cm", width="1cm", height="1cm")
page1.addElement(light1)
page1.addElement(light2)
page1.addElement(light3)

# Add instruction text
frame1 = Frame(width="15cm", height="2cm", x="2cm", y="1cm")
textbox1 = TextBox()
frame1.addElement(textbox1)
textbox1.addElement(P(text="Goal: Select all -> Shape -> Subtract"))
page1.addElement(frame1)


# --- Slide 2: Cloud Asset ---
page2 = Page(name="Cloud Asset")
doc.presentation.addElement(page2)

# Cloud Parts (Overlapping Ellipses) - to be unioned
# Center
c1 = Ellipse(style_name=cloud_style, x="8cm", y="6cm", width="4cm", height="4cm")
# Left
c2 = Ellipse(style_name=cloud_style, x="6cm", y="7cm", width="3cm", height="3cm")
# Right
c3 = Ellipse(style_name=cloud_style, x="11cm", y="7cm", width="3cm", height="3cm")
# Top Left
c4 = Ellipse(style_name=cloud_style, x="7cm", y="5cm", width="3cm", height="3cm")
# Top Right
c5 = Ellipse(style_name=cloud_style, x="10cm", y="5cm", width="3cm", height="3cm")

page2.addElement(c1)
page2.addElement(c2)
page2.addElement(c3)
page2.addElement(c4)
page2.addElement(c5)

# Add instruction text
frame2 = Frame(width="15cm", height="2cm", x="2cm", y="1cm")
textbox2 = TextBox()
frame2.addElement(textbox2)
textbox2.addElement(P(text="Goal: Select all -> Shape -> Union"))
page2.addElement(frame2)

doc.save("/home/ga/Documents/Presentations/icons_draft.odp")
print("Generated /home/ga/Documents/Presentations/icons_draft.odp")
PYEOF

# Fix permissions
sudo chown ga:ga /home/ga/Documents/Presentations/icons_draft.odp

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/icons_draft.odp > /tmp/impress_task.log 2>&1 &"
fi

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 60

# Focus Impress window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Ensure window is maximized for visibility
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="