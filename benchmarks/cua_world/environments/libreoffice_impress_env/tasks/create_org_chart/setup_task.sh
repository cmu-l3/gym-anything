#!/bin/bash
set -euo pipefail

echo "=== Setting up Create Org Chart task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Ensure working directory exists
WORK_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$WORK_DIR"

# Create the initial presentation using python-pptx
echo "Creating initial presentation..."
cat > /tmp/create_initial_presentation.py << 'PYEOF'
#!/usr/bin/env python3
"""Create the Acme Corp Annual Review presentation with 4 slides"""
import os
import sys

try:
    from pptx import Presentation
    from pptx.util import Inches, Pt
    from pptx.enum.text import PP_ALIGN
except ImportError:
    print("python-pptx not installed")
    sys.exit(1)

prs = Presentation()

# Set slide dimensions to widescreen 16:9
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

# --- Slide 1: Title Slide ---
slide1 = prs.slides.add_slide(prs.slide_layouts[0])
title1 = slide1.shapes.title
subtitle1 = slide1.placeholders[1]
title1.text = "Acme Corp Annual Review 2024"
subtitle1.text = "Building Tomorrow, Together"

# --- Slide 2: Financial Highlights ---
slide2 = prs.slides.add_slide(prs.slide_layouts[1])
title2 = slide2.shapes.title
title2.text = "Financial Highlights"
body2 = slide2.placeholders[1]
tf2 = body2.text_frame
tf2.text = "Annual revenue grew 18% year-over-year to $247M"
p = tf2.add_paragraph()
p.text = "Operating margin improved to 22.3%, up from 19.1%"
p = tf2.add_paragraph()
p.text = "Customer acquisition cost decreased by 14%"
p = tf2.add_paragraph()
p.text = "Expanded into 3 new international markets"

# --- Slide 3: Leadership Team (TARGET SLIDE - empty content) ---
# Use blank layout to avoid placeholder prompts interfering with agent
slide3 = prs.slides.add_slide(prs.slide_layouts[6]) 
# Add a title text box manually
txBox = slide3.shapes.add_textbox(Inches(0.5), Inches(0.2), Inches(12.33), Inches(1.0))
tf = txBox.text_frame
p = tf.paragraphs[0]
p.text = "Leadership Team"
p.font.size = Pt(40)
p.font.bold = True
p.alignment = PP_ALIGN.CENTER

# --- Slide 4: Next Steps ---
slide4 = prs.slides.add_slide(prs.slide_layouts[1])
title4 = slide4.shapes.title
title4.text = "Next Steps"
body4 = slide4.placeholders[1]
tf4 = body4.text_frame
tf4.text = "Complete Series C funding round by Q2 2025"
p = tf4.add_paragraph()
p.text = "Launch enterprise platform v3.0 in March"

# Save the presentation
output_path = os.path.expanduser("/home/ga/Documents/Presentations/acme_annual_review.pptx")
prs.save(output_path)
print(f"Presentation saved to {output_path}")
PYEOF

sudo -u ga python3 /tmp/create_initial_presentation.py

# Record initial file state for anti-gaming
if [ -f "$WORK_DIR/acme_annual_review.pptx" ]; then
    stat "$WORK_DIR/acme_annual_review.pptx" > /tmp/initial_file_stat.txt
else
    echo "ERROR: Failed to create initial presentation"
    exit 1
fi

# Launch LibreOffice Impress with the file
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$WORK_DIR/acme_annual_review.pptx' > /tmp/impress_startup.log 2>&1 &"

# Wait for Impress to open
if ! wait_for_window "LibreOffice Impress" 60; then
    # Fallback check for file name in title
    wait_for_window "acme" 30 || echo "WARNING: Window detection timed out"
fi

# Maximize the window
echo "Maximizing window..."
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (like Tip of the Day)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="