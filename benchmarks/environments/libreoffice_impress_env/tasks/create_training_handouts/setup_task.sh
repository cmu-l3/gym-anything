#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Training Handouts Task ==="

# 1. Create directory structure
sudo -u ga mkdir -p /home/ga/Documents/Presentations
sudo -u ga mkdir -p /home/ga/Documents/results

# 2. Generate the Safety Orientation ODP file programmatically
# We use odfpy which is installed in the environment
echo "Generating presentation file..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties, ParagraphProperties, DrawingPageProperties
from odf.draw import Page, Frame, TextBox, Image
from odf.text import P
import os

doc = OpenDocumentPresentation()

# Content for 10 slides
slides_content = [
    ("Workplace Safety Orientation 2025", ["Welcome to the team", "Safety is our #1 Priority", "Overview of protocols"]),
    ("Our Commitment", ["Zero Accident Vision", "Shared Responsibility", "Continuous Improvement"]),
    ("Fire Safety", ["PASS Method: Pull, Aim, Squeeze, Sweep", "Know your evacuation route", "Do not use elevators"]),
    ("Emergency Exits", ["Marked with green signs", "Keep clear at all times", "Assembly Point: Parking Lot B"]),
    ("First Aid", ["Kits located in break rooms", "AED available at reception", "Report all injuries immediately"]),
    ("Slips, Trips, and Falls", ["Keep walkways clear", "Clean spills immediately", "Use handrails on stairs"]),
    ("Electrical Safety", ["Inspect cords before use", "Do not overload circuits", "Lock-out / Tag-out procedures"]),
    ("Ergonomics", ["Lift with your legs, not back", "Adjust monitor height", "Take regular stretch breaks"]),
    ("PPE Requirements", ["Safety glasses in lab areas", "Steel-toed boots in warehouse", "High-visibility vests in yard"]),
    ("Emergency Contacts", ["Safety Officer: Ext 5555", "Security: Ext 5000", "Emergency Services: 911"])
]

def create_slide(doc, title_text, bullets):
    page = Page(name=title_text[:10])
    doc.presentation.addElement(page)

    # Title Frame
    title_frame = Frame(width="25cm", height="3cm", x="1.5cm", y="1cm")
    page.addElement(title_frame)
    title_box = TextBox()
    title_frame.addElement(title_box)
    title_box.addElement(P(text=title_text))

    # Content Frame
    content_frame = Frame(width="25cm", height="12cm", x="1.5cm", y="5cm")
    page.addElement(content_frame)
    content_box = TextBox()
    content_frame.addElement(content_box)
    
    for bullet in bullets:
        content_box.addElement(P(text=f"• {bullet}"))

for title, bullets in slides_content:
    create_slide(doc, title, bullets)

output_path = "/home/ga/Documents/Presentations/safety_orientation.odp"
doc.save(output_path)
print(f"Created {output_path}")
PYEOF

# Ensure correct permissions
sudo chown ga:ga /home/ga/Documents/Presentations/safety_orientation.odp

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch LibreOffice Impress with the file
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/safety_orientation.odp > /tmp/impress_task.log 2>&1 &"

# 5. Wait for application to load
wait_for_window "LibreOffice Impress" 60 || echo "WARNING: Window wait timeout"

# 6. Focus and Maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Dismiss potential recovery dialogs by pressing Esc
    safe_xdotool ga :1 key Escape
fi

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="