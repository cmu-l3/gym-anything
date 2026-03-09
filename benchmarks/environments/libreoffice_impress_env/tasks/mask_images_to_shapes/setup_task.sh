#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Mask Images to Shapes Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
sudo -u ga mkdir -p /home/ga/Documents/Presentations
sudo -u ga mkdir -p /tmp/assets

# Download assets (Computing Pioneers)
echo "Downloading assets..."
# Ada Lovelace
wget -q -O /tmp/assets/ada.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a4/Ada_Lovelace_portrait.jpg/400px-Ada_Lovelace_portrait.jpg"
# Grace Hopper
wget -q -O /tmp/assets/grace.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/5/55/Grace_Hopper.jpg/400px-Grace_Hopper.jpg"
# Alan Turing
wget -q -O /tmp/assets/alan.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a1/Alan_Turing_Aged_16.jpg/400px-Alan_Turing_Aged_16.jpg"

# Generate initial presentation using python-pptx (easier layout control)
# then convert to ODP
cat << 'PYEOF' > /tmp/create_pioneers.py
from pptx import Presentation
from pptx.util import Inches, Pt
import os

prs = Presentation()

# Slide 1: Title
title_slide_layout = prs.slide_layouts[0]
slide = prs.slides.add_slide(title_slide_layout)
title = slide.shapes.title
subtitle = slide.placeholders[1]
title.text = "Computing Pioneers"
subtitle.text = "Legends of Computer Science"

# Slide 2: Images
blank_slide_layout = prs.slide_layouts[6]
slide = prs.slides.add_slide(blank_slide_layout)

# Add Title Manually
left = Inches(1)
top = Inches(0.5)
width = Inches(8)
height = Inches(1)
txBox = slide.shapes.add_textbox(left, top, width, height)
tf = txBox.text_frame
tf.text = "The Pioneers"
p = tf.paragraphs[0]
p.font.size = Pt(40)
p.font.bold = True

# Add Images (Rectangular)
img_y = Inches(2.5)
img_h = Inches(3.5)

# Ada
if os.path.exists("/tmp/assets/ada.jpg"):
    slide.shapes.add_picture("/tmp/assets/ada.jpg", Inches(0.5), img_y, height=img_h)

# Grace
if os.path.exists("/tmp/assets/grace.jpg"):
    slide.shapes.add_picture("/tmp/assets/grace.jpg", Inches(3.75), img_y, height=img_h)

# Alan
if os.path.exists("/tmp/assets/alan.jpg"):
    slide.shapes.add_picture("/tmp/assets/alan.jpg", Inches(7.0), img_y, height=img_h)

prs.save("/tmp/computing_pioneers.pptx")
PYEOF

echo "Generating PPTX..."
python3 /tmp/create_pioneers.py

echo "Converting to ODP..."
# Use headless LibreOffice to convert PPTX to ODP for the task
# This ensures a native ODP structure
libreoffice --headless --convert-to odp --outdir /home/ga/Documents/Presentations /tmp/computing_pioneers.pptx

# Set permissions
chown -R ga:ga /home/ga/Documents/Presentations

# Record initial file state
FILE_PATH="/home/ga/Documents/Presentations/computing_pioneers.odp"
if [ -f "$FILE_PATH" ]; then
    stat -c %Y "$FILE_PATH" > /tmp/initial_file_mtime.txt
else
    echo "0" > /tmp/initial_file_mtime.txt
fi

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$FILE_PATH' > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 60

# Maximize window (Critical for VLM and visibility)
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Focusing and maximizing window $wid..."
    focus_window "$wid"
    # F11 usually toggles fullscreen, but we want maximized window. 
    # wmctrl is handled in wait_for_window utils or above, but let's reinforce.
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Ensure slide 2 is visible (navigate down one slide)
    sleep 2
    # Click to focus
    su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1"
    # Press Page Down to go to slide 2
    su - ga -c "DISPLAY=:1 xdotool key Page_Down"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="