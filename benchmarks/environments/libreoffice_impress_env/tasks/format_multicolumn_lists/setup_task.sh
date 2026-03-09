#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Format Multicolumn List Task ==="

# Define paths
PRESENTATION_DIR="/home/ga/Documents/Presentations"
FILE_PATH="$PRESENTATION_DIR/gala_sponsors.odp"

# Create directory
sudo -u ga mkdir -p "$PRESENTATION_DIR"

# Generate the ODP file with Python to ensure correct structure
echo "Generating presentation file..."
python3 << 'PYEOF'
import os
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties, ParagraphProperties
from odf.text import P
from odf.draw import Page, Frame, TextBox

doc = OpenDocumentPresentation()

# Create styles
# Standard title style
title_style = Style(name="TitleStyle", family="presentation")
title_style.addElement(ParagraphProperties(textalign="center"))
title_style.addElement(TextProperties(fontsize="44pt", fontfamily="Liberation Sans"))
doc.styles.addElement(title_style)

# Standard list style (single column initially)
list_style = Style(name="ListStyle", family="presentation")
list_style.addElement(ParagraphProperties(textalign="left"))
list_style.addElement(TextProperties(fontsize="24pt", fontfamily="Liberation Sans"))
doc.styles.addElement(list_style)

# --- Slide 1: Title ---
page1 = Page(name="Title Slide")
doc.presentation.addElement(page1)

frame1 = Frame(width="25cm", height="3cm", x="1.5cm", y="8cm")
textbox1 = TextBox()
textbox1.addElement(P(text="Annual Charity Gala 2025", stylename=title_style))
frame1.addElement(textbox1)
page1.addElement(frame1)

# --- Slide 2: The Problem Slide (Silver Sponsors) ---
page2 = Page(name="Sponsors")
doc.presentation.addElement(page2)

# Title
frame2_title = Frame(width="25cm", height="3cm", x="1.5cm", y="1cm")
textbox2_title = TextBox()
textbox2_title.addElement(P(text="Silver Sponsors", stylename=title_style))
frame2_title.addElement(textbox2_title)
page2.addElement(frame2_title)

# The long list (this will overflow or look bad in one column)
sponsors = [
    "Riverfront Catering Services",
    "TechStart Solutions",
    "Metro City Bank",
    "Westside Logistics Group",
    "Oak Tree Capital Partners",
    "Sunrise Health Systems",
    "Global Freight & Shipping",
    "Urban Design Architects",
    "Community First Credit Union",
    "Blue Horizon Media",
    "Vertex Engineering Labs",
    "North Star Insurance",
    "Harbor View Properties",
    "Citywide Transportation"
]

# Create a frame for the list
# Intentionally tall to contain them but showing the need for columns
frame2_list = Frame(width="24cm", height="14cm", x="2cm", y="4cm")
textbox2_list = TextBox()
for sponsor in sponsors:
    textbox2_list.addElement(P(text=sponsor, stylename=list_style))
frame2_list.addElement(textbox2_list)
page2.addElement(frame2_list)

# --- Slide 3: Closing ---
page3 = Page(name="Contact")
doc.presentation.addElement(page3)
frame3 = Frame(width="25cm", height="3cm", x="1.5cm", y="8cm")
textbox3 = TextBox()
textbox3.addElement(P(text="Thank You For Your Support", stylename=title_style))
frame3.addElement(textbox3)
page3.addElement(frame3)

# Save file
doc.save("/home/ga/Documents/Presentations/gala_sponsors.odp")
print("Presentation generated successfully.")
PYEOF

# Set permissions
sudo chown ga:ga "$FILE_PATH"

# Record start time and initial file state
date +%s > /tmp/task_start_time.txt
stat -c %Y "$FILE_PATH" > /tmp/initial_file_mtime.txt

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$FILE_PATH' > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 20
if wait_for_window "LibreOffice Impress" 60; then
    echo "Window detected."
else
    echo "WARNING: Impress window not detected, retrying detection..."
    sleep 5
fi

# Initial cleanup
sleep 5
echo "Maximizing window..."
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Ensure we are on Slide 1 initially to make the agent navigate
    safe_xdotool ga :1 key Home
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="