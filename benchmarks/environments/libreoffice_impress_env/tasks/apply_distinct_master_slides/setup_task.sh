#!/bin/bash
set -euo pipefail

echo "=== Setting up Apply Distinct Master Slides Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents/Presentations
sudo -u ga mkdir -p /home/ga/Desktop

# Generate assets using python3 and odfpy (available in env)
echo "Generating presentation assets..."
cat << 'PYEOF' > /tmp/generate_assets.py
import os
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties
from odf.draw import Page, Frame, TextBox
from odf.text import P

def create_midnight_template():
    # Create a template with a dark background
    doc = OpenDocumentPresentation()
    
    # Define page layout
    pl = PageLayout(name="PM1")
    doc.automaticstyles.addElement(pl)
    pl.addElement(PageLayoutProperties(backgroundcolor="#1a1a2e", margin="0cm"))
    
    # Define master page
    master = MasterPage(name="Midnight", pagelayoutname=pl)
    doc.masterstyles.addElement(master)
    
    # Save
    doc.save("/home/ga/Desktop/Midnight.otp")
    print("Created Midnight.otp")

def create_presentation():
    doc = OpenDocumentPresentation()
    
    # Content for 7 slides
    slides_data = [
        ("Q3 Marketing Performance", "Executive Summary"),
        ("Agenda", "1. KPI Overview\n2. Channel Analysis\n3. Next Steps"),
        ("Digital Channels", "Section 1"),
        ("Social Media Growth", "LinkedIn: +15%\nTwitter: +5%"),
        ("Website Traffic", "Unique Visitors: 45k\nBounce Rate: 42%"),
        ("Events & Outreach", "Section 2"),
        ("Next Steps", "Optimize Ad Spend\nLaunch Q4 Campaign")
    ]
    
    for title, content in slides_data:
        page = Page(name=title)
        doc.presentation.addElement(page)
        
        # Title
        frame_t = Frame(width="25cm", height="3cm", x="1cm", y="1cm")
        tb_t = TextBox()
        frame_t.addElement(tb_t)
        tb_t.addElement(P(text=title))
        page.addElement(frame_t)
        
        # Content
        frame_c = Frame(width="25cm", height="10cm", x="1cm", y="5cm")
        tb_c = TextBox()
        frame_c.addElement(tb_c)
        tb_c.addElement(P(text=content))
        page.addElement(frame_c)

    doc.save("/home/ga/Documents/Presentations/Q3_Marketing_Review.odp")
    print("Created Q3_Marketing_Review.odp")

if __name__ == "__main__":
    create_midnight_template()
    create_presentation()
PYEOF

# Run generation script as ga user
sudo -u ga python3 /tmp/generate_assets.py

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/Q3_Marketing_Review.odp > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 90

# Focus window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Click to dismiss any focus issues
    su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="