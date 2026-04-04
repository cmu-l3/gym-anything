#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Annotate Dashboard Screenshot Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents/Presentations
sudo -u ga mkdir -p /home/ga/Documents/assets

# 1. Generate the Dashboard Image using Python (PIL)
# We use PIL (Pillow) which is installed in the environment
echo "Generating dashboard chart..."
python3 << 'PYEOF'
from PIL import Image, ImageDraw, ImageFont
import os

# Create image
width, height = 1024, 768
img = Image.new('RGB', (width, height), color='white')
d = ImageDraw.Draw(img)

# Define chart area
margin = 100
chart_w = width - 2*margin
chart_h = height - 2*margin
baseline = height - margin

# Data
quarters = ['Q1', 'Q2', 'Q3', 'Q4']
values = [500, 520, 250, 550] # Q3 is the dip
colors = ['#808080', '#808080', '#FF0000', '#808080'] # Q3 is red

# Draw axes
d.line([(margin, margin), (margin, baseline)], fill='black', width=3) # Y axis
d.line([(margin, baseline), (width-margin, baseline)], fill='black', width=3) # X axis

# Draw bars
bar_width = 100
spacing = (chart_w - (len(values) * bar_width)) / (len(values) + 1)

for i, val in enumerate(values):
    x = margin + spacing + i * (bar_width + spacing)
    bar_height = val
    y = baseline - bar_height
    
    # Draw bar
    d.rectangle([x, y, x + bar_width, baseline], fill=colors[i], outline='black')
    
    # Draw label
    # Simple text centering
    d.text((x + 35, baseline + 20), quarters[i], fill='black')

# Add Title
d.text((width//2 - 100, 30), "Annual Revenue Performance 2024", fill='black', align="center")

# Save
img.save("/home/ga/Documents/assets/dashboard.png")
print("Dashboard image saved to /home/ga/Documents/assets/dashboard.png")
PYEOF

# 2. Create the ODP Presentation with the image
echo "Creating ODP presentation..."
python3 << 'PYEOF'
import os
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, Image
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties

doc = OpenDocumentPresentation()

# Create a slide
page = Page(name="Revenue Analysis")
doc.presentation.addElement(page)

# Add the image to the slide
# In ODF, we create a frame and put an image inside it
# Position: Centered roughly
img_path = "/home/ga/Documents/assets/dashboard.png"

photo_frame = Frame(width="24cm", height="18cm", x="2cm", y="2cm")
img = Image(href=img_path)
photo_frame.addElement(img)
page.addElement(photo_frame)

# Save
doc.save("/home/ga/Documents/Presentations/revenue_analysis.odp")
print("Presentation created.")
PYEOF

# Set permissions
sudo chown -R ga:ga /home/ga/Documents

# 3. Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/revenue_analysis.odp > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 60

# Focus window and maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Focusing window ID: $wid"
    focus_window "$wid"
    # Maximize
    safe_xdotool ga :1 key F11
    sleep 1
    # Ensure slide pane is active (click roughly in center)
    safe_xdotool ga :1 mousemove 960 540 click 1
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="