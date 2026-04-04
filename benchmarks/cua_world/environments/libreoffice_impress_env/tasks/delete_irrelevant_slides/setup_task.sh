#!/bin/bash
set -euo pipefail

echo "=== Setting up delete_irrelevant_slides task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directory
mkdir -p /home/ga/Documents/Presentations

# Clean up previous files
rm -f /home/ga/Documents/Presentations/bia_report.pptx
rm -f /home/ga/Documents/Presentations/bia_report.odp

# Generate the 10-slide PPTX using python-pptx (installed in env)
echo "Generating presentation file..."
python3 << 'PYEOF'
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
import os

prs = Presentation()

# Define content
slides_data = [
    {"title": "Business Impact Analysis Report", "content": "Q4 2024 Assessment Cycle"},
    {"title": "Executive Summary", "content": "Max outage for Tier 1: 4 hours"},
    {"title": "IT Infrastructure Assessment", "content": "Uptime: 99.97%"},
    {"title": "Critical Business Functions", "content": "Payroll, Benefits, Compliance"},
    {"title": "Risk Assessment Matrix", "content": "Cyberattack: High Probability"},
    {"title": "Supply Chain Dependencies", "content": "47 Tier 1 suppliers evaluated"},
    {"title": "Recovery Time Objectives", "content": "Tier 1: 0-4 hours"},
    {"title": "Communication Plan", "content": "Emergency notification system"},
    {"title": "Vendor Management", "content": "218 active contracts reviewed"},
    {"title": "Action Items and Next Steps", "content": "Conduct recovery exercise"}
]

for slide_info in slides_data:
    layout = prs.slide_layouts[1] # Title and Content
    slide = prs.slides.add_slide(layout)
    
    # Title
    title = slide.shapes.title
    title.text = slide_info["title"]
    
    # Content
    body = slide.placeholders[1]
    tf = body.text_frame
    tf.text = slide_info["content"]

output_path = "/home/ga/Documents/Presentations/bia_report.pptx"
prs.save(output_path)
print(f"Saved {output_path}")
PYEOF

# Fix permissions
chown -R ga:ga /home/ga/Documents/Presentations

# Record initial file hash
md5sum /home/ga/Documents/Presentations/bia_report.pptx > /tmp/initial_file_hash.txt

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/bia_report.pptx > /tmp/impress.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 60

# Maximize and focus
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Ensure maximized
    DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any "Tip of the Day" or recovery dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="