#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Interactive Form Slide Task ==="

# 1. Prepare Directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# 2. Generate the starting Presentation with Realistic Content using odfpy
# We use the system python which has odfpy installed
cat << 'PY_SCRIPT' > /tmp/gen_presentation.py
import os
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, ParagraphProperties, GraphicProperties
from odf.text import P
from odf.draw import Page, Frame, TextBox, Image

doc = OpenDocumentPresentation()

# Create styles
title_style = Style(name="TitleStyle", family="presentation")
title_style.addElement(ParagraphProperties(text_align="center"))
title_style.addElement(TextProperties(font_size="44pt", font_weight="bold", color="#003366"))
doc.styles.addElement(title_style)

body_style = Style(name="BodyStyle", family="presentation")
body_style.addElement(TextProperties(font_size="24pt", color="#333333"))
doc.styles.addElement(body_style)

label_style = Style(name="LabelStyle", family="presentation")
label_style.addElement(TextProperties(font_size="18pt", font_weight="bold"))
doc.styles.addElement(label_style)

def add_slide(doc, name, title_text, content_lines=[]):
    page = Page(name=name)
    doc.presentation.addElement(page)

    # Title Frame
    title_frame = Frame(width="25cm", height="3cm", x="1.5cm", y="1cm")
    title_textbox = TextBox()
    title_textbox.addElement(P(text=title_text, stylename=title_style))
    title_frame.addElement(title_textbox)
    page.addElement(title_frame)

    # Content Frame
    content_frame = Frame(width="25cm", height="12cm", x="1.5cm", y="5cm")
    content_textbox = TextBox()
    for line in content_lines:
        content_textbox.addElement(P(text=line, stylename=body_style))
    content_frame.addElement(content_textbox)
    page.addElement(content_frame)
    return page

# Slide 1: Title
add_slide(doc, "Slide1", "Warehouse Safety Protocols 2026", 
          ["", "Mandatory Training for All Staff", "Q1 Update"])

# Slide 2: PPE
add_slide(doc, "Slide2", "PPE Requirements", 
          ["• Hard Hats must be worn in Zone A", "• High-visibility vests required at all times", "• Steel-toed boots mandatory"])

# Slide 3: Emergency
add_slide(doc, "Slide3", "Emergency Procedures", 
          ["• Fire Exits located at North and South Gates", "• Assembly Point: Parking Lot B", "• Do not use elevators during alarm"])

# Slide 4: Lifting
add_slide(doc, "Slide4", "Safe Lifting Techniques", 
          ["• Bend at the knees, not the back", "• Keep load close to body", "• Ask for assistance for loads > 20kg"])

# Slide 5: Pledge (Target Slide)
page5 = Page(name="Slide5")
doc.presentation.addElement(page5)

# Title
t_frame = Frame(width="25cm", height="3cm", x="1.5cm", y="1cm")
t_box = TextBox()
t_box.addElement(P(text="Safety Pledge", stylename=title_style))
t_frame.addElement(t_box)
page5.addElement(t_frame)

# Static Label: Employee Name
l1_frame = Frame(width="8cm", height="2cm", x="2cm", y="5cm")
l1_box = TextBox()
l1_box.addElement(P(text="Employee Name:", stylename=label_style))
l1_frame.addElement(l1_box)
page5.addElement(l1_frame)

# Static Label: Agreement Text
l2_frame = Frame(width="20cm", height="3cm", x="2cm", y="8cm")
l2_box = TextBox()
l2_box.addElement(P(text="I certify that I have read and understood the Warehouse Safety Protocols 2026.", stylename=body_style))
l2_frame.addElement(l2_box)
page5.addElement(l2_frame)

doc.save("/home/ga/Documents/Presentations/warehouse_safety.odp")
PY_SCRIPT

python3 /tmp/gen_presentation.py
sudo chown ga:ga /home/ga/Documents/Presentations/warehouse_safety.odp
rm /tmp/gen_presentation.py

# 3. Setup Anti-Gaming
date +%s > /tmp/task_start_time.txt
# Record initial file hash/timestamp
stat -c %Y /home/ga/Documents/Presentations/warehouse_safety.odp > /tmp/initial_file_mtime.txt

# 4. Launch Application
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/warehouse_safety.odp > /tmp/impress.log 2>&1 &"

# 5. Wait for Readiness
wait_for_window "LibreOffice Impress" 60

# 6. Ensure Window State
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
    sleep 1
    # Dismiss any recovery dialogs if they appear (Esc key)
    safe_xdotool ga :1 key Escape
fi

# 7. Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="