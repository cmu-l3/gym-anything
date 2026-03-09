#!/bin/bash
set -e
echo "=== Setting up duplicate_regional_slides task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Define file paths
PPTX_PATH="/home/ga/Documents/Presentations/quarterly_review.pptx"
ODP_PATH="/home/ga/Documents/Presentations/quarterly_review.odp"

# Clean up previous runs
rm -f "$PPTX_PATH" "$ODP_PATH" 2>/dev/null || true

# Generate the initial presentation using python-pptx (easier programmatic generation)
# We will convert it to ODP immediately after.
python3 << 'PYEOF'
from pptx import Presentation
from pptx.util import Inches, Pt

prs = Presentation()

# Slide 1: Quarterly Sales Overview
slide1 = prs.slides.add_slide(prs.slide_layouts[1])  # Title and Content
slide1.shapes.title.text = "Quarterly Sales Overview"
body1 = slide1.placeholders[1]
tf1 = body1.text_frame
tf1.text = "Total Revenue: $4.2M"
p = tf1.add_paragraph()
p.text = "Year-over-Year Growth: 12%"
p = tf1.add_paragraph()
p.text = "New Customers: 47"

# Slide 2: Top Performing Products
slide2 = prs.slides.add_slide(prs.slide_layouts[1])
slide2.shapes.title.text = "Top Performing Products"
body2 = slide2.placeholders[1]
tf2 = body2.text_frame
tf2.text = "Enterprise Suite: $1.8M"
p = tf2.add_paragraph()
p.text = "Cloud Platform: $1.3M"
p = tf2.add_paragraph()
p.text = "Support Services: $1.1M"

# Slide 3: Next Quarter Priorities
slide3 = prs.slides.add_slide(prs.slide_layouts[1])
slide3.shapes.title.text = "Next Quarter Priorities"
body3 = slide3.placeholders[1]
tf3 = body3.text_frame
tf3.text = "Expand into healthcare vertical"
p = tf3.add_paragraph()
p.text = "Launch partner program"
p = tf3.add_paragraph()
p.text = "Increase retention rate to 95%"

prs.save("/home/ga/Documents/Presentations/quarterly_review.pptx")
PYEOF

# Convert PPTX to ODP using LibreOffice headless
echo "Converting generated PPTX to ODP..."
cd /home/ga/Documents/Presentations/
libreoffice --headless --convert-to odp "$PPTX_PATH" > /dev/null 2>&1
sleep 2

if [ ! -f "$ODP_PATH" ]; then
    echo "ERROR: Failed to create ODP file"
    exit 1
fi

# Cleanup PPTX
rm "$PPTX_PATH"

# Set ownership
chown ga:ga "$ODP_PATH"

# Record initial slide count (should be 3)
echo "3" > /tmp/initial_slide_count.txt

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$ODP_PATH' > /tmp/impress.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Impress" 30

# Maximize window
DISPLAY=:1 wmctrl -r "LibreOffice Impress" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="