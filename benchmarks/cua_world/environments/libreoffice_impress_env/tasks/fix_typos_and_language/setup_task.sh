#!/bin/bash
set -euo pipefail

echo "=== Setting up Fix Typos and Language Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Generate the ODP file with specific errors using python
# We use odfpy which is installed in the environment
cat << 'PY_SCRIPT' > /tmp/generate_presentation.py
import os
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties, ParagraphProperties
from odf.text import P
from odf.draw import Page, Frame, TextBox

def create_text_box(page, x, y, width, height, text_content, style_name=None):
    frame = Frame(width=width, height=height, x=x, y=y)
    textbox = TextBox()
    frame.addElement(textbox)
    
    if isinstance(text_content, list):
        for line in text_content:
            p = P(text=line)
            if style_name:
                p.setAttribute("stylename", style_name)
            textbox.addElement(p)
    else:
        p = P(text=text_content)
        if style_name:
            p.setAttribute("stylename", style_name)
        textbox.addElement(p)
    
    page.addElement(frame)

doc = OpenDocumentPresentation()

# Define styles
# Force English language to ensure the French text gets flagged as error initially
en_style = Style(name="ForceEnglish", family="paragraph")
en_style.addElement(TextProperties(language="en", country="US"))
doc.styles.addElement(en_style)

# Slide 1: Title
page1 = Page(name="Title")
doc.presentation.addElement(page1)
create_text_box(page1, "2cm", "4cm", "24cm", "3cm", "Global Health Summit 2024")
create_text_box(page1, "2cm", "8cm", "24cm", "2cm", "Strategic Planning Draft")

# Slide 2: Challenges (With Typos)
page2 = Page(name="Key Challenges")
doc.presentation.addElement(page2)
create_text_box(page2, "2cm", "2cm", "24cm", "2cm", "Key Challenges")
bullets = [
    "1. Unequal resource distrubution across regions",
    "2. Rising costs for paitents in rural areas",
    "3. Language barriar in cross-border cooperation"
]
create_text_box(page2, "2cm", "5cm", "24cm", "10cm", bullets, style_name="ForceEnglish")

# Slide 3: French Content (Incorrectly marked as English)
page3 = Page(name="Partenariat Stratégique")
doc.presentation.addElement(page3)
create_text_box(page3, "2cm", "2cm", "24cm", "2cm", "Partenariat Stratégique")
french_text = "Nous devons collaborer pour améliorer la santé mondiale. " \
              "La distribution équitable des médicaments est essentielle."
# We apply the 'ForceEnglish' style so spellcheck flags this
create_text_box(page3, "2cm", "5cm", "24cm", "5cm", french_text, style_name="ForceEnglish")

output_path = "/home/ga/Documents/Presentations/global_health_summit.odp"
doc.save(output_path)
print(f"Created presentation at {output_path}")
PY_SCRIPT

# Run the generation script
echo "Generating presentation file..."
python3 /tmp/generate_presentation.py
sudo chown ga:ga /home/ga/Documents/Presentations/global_health_summit.odp

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/global_health_summit.odp > /tmp/impress_task.log 2>&1 &"

# Wait for process
wait_for_process "soffice" 20

# Wait for window
wait_for_window "LibreOffice Impress" 60

# Maximize window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Focusing and maximizing window $wid"
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any recovery/tip dialogs if they appear
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Click in the center to ensure focus is on the slide pane/edit view
DISPLAY=:1 xdotool mousemove 960 540 click 1

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="