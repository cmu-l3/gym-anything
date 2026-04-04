#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Master Slide Navigation Task ==="

# 1. Create directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# 2. Generate the starting ODP file with specific slides using Python
# We use the system python which has odfpy installed
python3 << 'PYEOF'
import os
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties

output_path = "/home/ga/Documents/Presentations/employee_handbook.odp"

doc = OpenDocumentPresentation()

# Define slide titles
titles = ["Welcome", "Company Policies", "Benefits Overview", "IT Setup", "HR Contacts"]

for i, title in enumerate(titles):
    # Create page
    page = Page(name=f"Slide{i+1}")
    doc.presentation.addElement(page)
    
    # Add title frame
    frame = Frame(width="25cm", height="3cm", x="2cm", y="2cm")
    page.addElement(frame)
    
    textbox = TextBox()
    frame.addElement(textbox)
    
    # Add title text with some formatting usually handled by styles, 
    # but here we just put plain text
    p = P(text=title)
    textbox.addElement(p)
    
    # Add some dummy content
    content_frame = Frame(width="25cm", height="10cm", x="2cm", y="6cm")
    page.addElement(content_frame)
    content_box = TextBox()
    content_frame.addElement(content_box)
    content_box.addElement(P(text=f"Content for section: {title}"))

doc.save(output_path)
print(f"Created {output_path}")
PYEOF

# Ensure permissions
sudo chown ga:ga /home/ga/Documents/Presentations/employee_handbook.odp

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/employee_handbook.odp > /tmp/impress_task.log 2>&1 &"

# 5. Wait for application
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
fi

if ! wait_for_window "LibreOffice Impress" 60; then
    echo "ERROR: Window did not appear"
fi

# 6. Focus and Maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    safe_xdotool ga :1 key F11
    sleep 0.5
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="