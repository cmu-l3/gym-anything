#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Convert List to Process Diagram Task ==="

# Create directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create the initial presentation using python/odfpy
# We create a title slide and a content slide with a bullet list
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P, List, ListItem
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties

doc = OpenDocumentPresentation()

# Slide 1: Title
page1 = Page(name="Slide1")
doc.presentation.addElement(page1)

frame1 = Frame(width="720pt", height="56pt", x="56pt", y="42pt")
page1.addElement(frame1)
textbox1 = TextBox()
frame1.addElement(textbox1)
p1 = P(text="Project Alpha Launch")
textbox1.addElement(p1)

# Slide 2: Roadmap List
page2 = Page(name="Slide2")
doc.presentation.addElement(page2)

# Title for Slide 2
frame2_title = Frame(width="720pt", height="56pt", x="56pt", y="42pt")
page2.addElement(frame2_title)
textbox2_title = TextBox()
frame2_title.addElement(textbox2_title)
p2_title = P(text="Phase Roadmap")
textbox2_title.addElement(p2_title)

# Content List
frame2_content = Frame(width="720pt", height="400pt", x="56pt", y="120pt")
page2.addElement(frame2_content)
textbox2_content = TextBox()
frame2_content.addElement(textbox2_content)

# Create list
list_content = ["Market Analysis", "Prototype Development", "Global Release"]
ul = List()
for item in list_content:
    li = ListItem()
    li.addElement(P(text=item))
    ul.addElement(li)

textbox2_content.addElement(ul)

doc.save("/home/ga/Documents/Presentations/product_launch_roadmap.odp")
print("Presentation created successfully")
PYEOF

# Ensure permissions
sudo chown ga:ga /home/ga/Documents/Presentations/product_launch_roadmap.odp

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/product_launch_roadmap.odp > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 90

# Dismiss any recovery dialogs or tips if they appear
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Click to ensure focus
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Maximize window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Ensure it's maximized
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="