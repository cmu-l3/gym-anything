#!/bin/bash
set -e
echo "=== Setting up task: customize_bullet_style ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create the initial presentation using python-pptx
# We generate a PPTX first, then convert to ODP to ensure a clean "imported" state 
# which often happens in real workflows and ensures standard XML structure.
cat > /tmp/gen_pres.py << 'EOF'
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.enum.text import PP_ALIGN

prs = Presentation()

# Use a blank layout
blank_slide_layout = prs.slide_layouts[6]
slide = prs.slides.add_slide(blank_slide_layout)

# Add Title
left = Inches(1)
top = Inches(0.5)
width = Inches(8)
height = Inches(1)
title = slide.shapes.add_textbox(left, top, width, height)
tf = title.text_frame
p = tf.paragraphs[0]
p.text = "Q3 Launch Readiness"
p.font.size = Pt(44)
p.font.bold = True
p.alignment = PP_ALIGN.CENTER

# Add Bullet List
# Real data from LibreOffice Release Notes
features = [
    "Support for zoom gestures when using touchpads",
    "Document themes support in Writer",
    "QR Code generator improvements",
    "Export to PDF updates and accessibility fixes",
    "LanguageTool remote grammar checker enabled"
]

left = Inches(1.5)
top = Inches(2.0)
width = Inches(7)
height = Inches(5)

body = slide.shapes.add_textbox(left, top, width, height)
tf = body.text_frame
tf.word_wrap = True

for feature in features:
    p = tf.add_paragraph()
    p.text = feature
    p.font.size = Pt(28)
    p.level = 0
    # Default bullets will be applied by LO upon import
    
prs.save('/tmp/release_readiness.pptx')
EOF

echo "Generating base presentation..."
python3 /tmp/gen_pres.py

# Convert to ODP using LibreOffice headless
echo "Converting to ODP..."
libreoffice --headless --convert-to odp --outdir /home/ga/Documents/Presentations /tmp/release_readiness.pptx 2>/dev/null

# Set permissions
chown -R ga:ga /home/ga/Documents

# Record initial file state
FILE_PATH="/home/ga/Documents/Presentations/release_readiness.odp"
if [ -f "$FILE_PATH" ]; then
    stat -c %Y "$FILE_PATH" > /tmp/initial_mtime.txt
    stat -c %s "$FILE_PATH" > /tmp/initial_size.txt
else
    echo "ERROR: Failed to create initial ODP file"
    exit 1
fi

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --impress $FILE_PATH > /tmp/impress.log 2>&1 &"
else
    # If already running, open the file
    su - ga -c "DISPLAY=:1 libreoffice --impress $FILE_PATH &"
fi

# Wait for window
wait_for_window "LibreOffice Impress" 60

# Maximize window
WID=$(get_impress_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss "Tip of the Day" if it appears
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="