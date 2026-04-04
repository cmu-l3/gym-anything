#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Sales Funnel Diagram Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create initial presentation using python-pptx then convert to ODP
# (Easier to programmatically generate a clean starter file this way)
echo "Generating starter presentation..."
cat << 'PYEOF' | python3
from pptx import Presentation
import sys

try:
    prs = Presentation()
    
    # Title Slide
    slide_layout = prs.slide_layouts[0]
    slide = prs.slides.add_slide(slide_layout)
    title = slide.shapes.title
    title.text = "Q1 Sales Pipeline Analysis"
    subtitle = slide.placeholders[1]
    subtitle.text = "CONFIDENTIAL - Internal Review"
    
    prs.save("/home/ga/Documents/Presentations/pipeline_review.pptx")
    print("Created PPTX starter file")
except Exception as e:
    print(f"Error creating starter file: {e}")
    sys.exit(1)
PYEOF

# Convert to ODP
libreoffice --headless --convert-to odp --outdir "/home/ga/Documents/Presentations" "/home/ga/Documents/Presentations/pipeline_review.pptx"
rm "/home/ga/Documents/Presentations/pipeline_review.pptx"
chown ga:ga "/home/ga/Documents/Presentations/pipeline_review.odp"

# Record initial file state
stat -c %Y "/home/ga/Documents/Presentations/pipeline_review.odp" > /tmp/initial_mtime.txt

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/pipeline_review.odp > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 60

# Maximize window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key F11  # Fullscreen/Maximize
    sleep 1
    # Click to ensure focus on the slide area
    safe_xdotool ga :1 mousemove 960 540 click 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="