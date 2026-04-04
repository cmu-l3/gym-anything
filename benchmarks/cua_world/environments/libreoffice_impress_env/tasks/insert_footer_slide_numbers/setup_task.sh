#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Insert Footer and Slide Numbers Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directory exists
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Generate the initial presentation using python-pptx (then convert to ODP)
# We use python-pptx because it's easier to script content generation, 
# and converting to ODP ensures a clean native LibreOffice file structure.
cat > /tmp/generate_pres.py << 'PYEOF'
from pptx import Presentation
from pptx.util import Inches, Pt

prs = Presentation()

# Slide 1: Title
slide = prs.slides.add_slide(prs.slide_layouts[0])
title = slide.shapes.title
subtitle = slide.placeholders[1]
title.text = "Operations Division Q4 2024 Review"
subtitle.text = "Quarterly Performance Summary\nPrepared for Board of Directors"

# Slide 2: Metrics
slide = prs.slides.add_slide(prs.slide_layouts[1])
slide.shapes.title.text = "Key Performance Metrics"
body = slide.shapes.placeholders[1]
tf = body.text_frame
tf.text = "Revenue: $12.4M (up 8% YoY)"
p = tf.add_paragraph()
p.text = "CSAT: 94.2%"
p = tf.add_paragraph()
p.text = "On-time Delivery: 97.1%"
p = tf.add_paragraph()
p.text = "Defect Rate: 0.3%"

# Slide 3: Projects
slide = prs.slides.add_slide(prs.slide_layouts[1])
slide.shapes.title.text = "Project Portfolio Status"
body = slide.shapes.placeholders[1]
body.text = "ERP Migration: 85% complete"
p = body.text_frame.add_paragraph()
p.text = "Warehouse Automation: On track for March"
p = body.text_frame.add_paragraph()
p.text = "Supplier Portal: In UAT phase"

# Slide 4: Financials
slide = prs.slides.add_slide(prs.slide_layouts[1])
slide.shapes.title.text = "Financial Summary"
body = slide.shapes.placeholders[1]
body.text = "OpEx: $8.7M (4% under budget)"
p = body.text_frame.add_paragraph()
p.text = "CapEx: $2.1M"
p = body.text_frame.add_paragraph()
p.text = "Headcount: 342 FTEs"

# Slide 5: Highlights
slide = prs.slides.add_slide(prs.slide_layouts[1])
slide.shapes.title.text = "Team Highlights"
body = slide.shapes.placeholders[1]
body.text = "3 new hires onboarded in Logistics"
p = body.text_frame.add_paragraph()
p.text = "Safety Milestone: 180 days incident-free"
p = body.text_frame.add_paragraph()
p.text = "Employee Engagement Score: 4.2/5.0"

# Slide 6: Future
slide = prs.slides.add_slide(prs.slide_layouts[1])
slide.shapes.title.text = "Q1 2025 Priorities"
body = slide.shapes.placeholders[1]
body.text = "Complete ERP migration"
p = body.text_frame.add_paragraph()
p.text = "Launch predictive maintenance pilot"
p = body.text_frame.add_paragraph()
p.text = "Expand Southeast distribution hub"

prs.save("/tmp/temp_pres.pptx")
PYEOF

echo "Generating content..."
python3 /tmp/generate_pres.py

echo "Converting to ODP..."
# Convert to ODP using headless LibreOffice to ensure native format
# This creates /tmp/temp_pres.odp
libreoffice --headless --convert-to odp --outdir /home/ga/Documents/Presentations /tmp/temp_pres.pptx

# Rename to final filename
mv /home/ga/Documents/Presentations/temp_pres.odp /home/ga/Documents/Presentations/q4_operations_review.odp
rm /tmp/temp_pres.pptx /tmp/generate_pres.py

# Set permissions
chown ga:ga /home/ga/Documents/Presentations/q4_operations_review.odp

# Record initial file state
stat -c %Y /home/ga/Documents/Presentations/q4_operations_review.odp > /tmp/initial_file_mtime.txt

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/q4_operations_review.odp > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 60 || wait_for_window "q4_operations_review" 60

# Maximize window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Focusing and maximizing window $wid..."
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
    
    # Dismiss any recovery dialogs if they appear
    safe_xdotool ga :1 key Escape
    sleep 1
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="