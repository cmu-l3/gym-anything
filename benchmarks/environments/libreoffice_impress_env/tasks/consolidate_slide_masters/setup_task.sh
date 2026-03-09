#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Consolidate Slide Masters Task ==="

# 1. Create directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# 2. Generate the "Franken-deck" using python and odfpy
# This script creates a presentation with 4 different master pages
echo "Generating inconsistent presentation..."
cat << 'PYEOF' > /tmp/generate_deck.py
import sys
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, DrawingPageProperties, TextProperties, ParagraphProperties
from odf.draw import Page, Frame, TextBox
from odf.text import P

def create_master(doc, name, color_hex):
    """Create a master page with a specific solid background color"""
    # Create the background style
    bg_style_name = f"{name}_BG"
    bg_style = Style(name=bg_style_name, family="drawing-page")
    bg_style.addElement(DrawingPageProperties(fill="solid", fillcolor=color_hex))
    doc.automaticstyles.addElement(bg_style)
    
    # Create the master page
    master = MasterPage(name=name, pagelayoutname="PM1")
    master.setAttribute('stylename', bg_style_name)
    doc.masterstyles.addElement(master)
    return name

def add_slide(doc, master_name, title_text):
    """Add a slide using the specified master"""
    page = Page(masterpagename=master_name)
    
    # Add Title Box (approximate positioning)
    frame = Frame(width="24cm", height="3cm", x="2cm", y="2cm")
    textbox = TextBox()
    frame.addElement(textbox)
    
    # Title Text Style
    p_style = Style(name=f"Title_{title_text.split()[0]}", family="paragraph")
    p_style.addElement(TextProperties(fontsize="44pt", fontfamily="Liberation Sans"))
    doc.automaticstyles.addElement(p_style)
    
    p = P(stylename=p_style, text=title_text)
    textbox.addElement(p)
    page.addElement(frame)
    
    doc.presentation.addElement(page)

# Initialize Doc
doc = OpenDocumentPresentation()

# Create Masters
# Corporate Blue (Correct)
blue_master = create_master(doc, "Corporate_Blue", "#E3F2FD") 
# Inconsistent Legacy Masters
red_master = create_master(doc, "Legacy_Red", "#FFEBEE")
green_master = create_master(doc, "Legacy_Green", "#E8F5E9")
yellow_master = create_master(doc, "Legacy_Yellow", "#FFFDE7")

# Create Slides with mixed masters
add_slide(doc, blue_master, "Q3 Sales Overview")   # Slide 1 (Reference)
add_slide(doc, red_master, "North Region Data")    # Slide 2 (Wrong)
add_slide(doc, green_master, "East Region Data")   # Slide 3 (Wrong)
add_slide(doc, yellow_master, "South Region Data") # Slide 4 (Wrong)
add_slide(doc, blue_master, "Global Summary")      # Slide 5 (Correct)

# Save
doc.save("/home/ga/Documents/Presentations/Q3_Global_Sales_Report.odp")
print("Presentation generated successfully.")
PYEOF

# Run the python script
python3 /tmp/generate_deck.py
rm /tmp/generate_deck.py

# Ensure ownership
sudo chown ga:ga /home/ga/Documents/Presentations/Q3_Global_Sales_Report.odp

# 3. Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/Q3_Global_Sales_Report.odp > /tmp/impress_task.log 2>&1 &"

# 4. Wait for application
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    exit 1
fi

if ! wait_for_window "LibreOffice Impress" 60; then
    echo "ERROR: LibreOffice window not detected"
    exit 1
fi

# 5. Focus and Optimize Window
echo "Focusing window..."
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Ensure sidebar is open (View -> Sidebar, F11 usually toggles styles, Ctrl+F5 sidebar)
    # We'll just click in the center to focus content
    safe_xdotool ga :1 mousemove 600 400 click 1
fi

# 6. Record Anti-Gaming Timestamps
date +%s > /tmp/task_start_time.txt
stat -c %Y /home/ga/Documents/Presentations/Q3_Global_Sales_Report.odp > /tmp/initial_file_mtime.txt

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="