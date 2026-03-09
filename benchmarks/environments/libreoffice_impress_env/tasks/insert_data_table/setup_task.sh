#!/bin/bash
set -e
echo "=== Setting up insert_data_table task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

PRES_DIR="/home/ga/Documents/Presentations"
PRES_FILE="$PRES_DIR/renewable_energy_report.pptx"

# Ensure directory exists
mkdir -p "$PRES_DIR"
chown -R ga:ga "$PRES_DIR"

# Kill any existing LibreOffice instances cleanly
echo "Cleaning up existing LibreOffice instances..."
pkill -f soffice 2>/dev/null || true
sleep 2

# Remove LibreOffice lock files
rm -f /home/ga/.config/libreoffice/4/.lock 2>/dev/null || true
rm -rf /home/ga/.config/libreoffice/4/user/.~lock.* 2>/dev/null || true
rm -f "$PRES_DIR/.~lock."* 2>/dev/null || true

# Create the initial presentation using python-pptx
echo "Creating initial presentation..."
su - ga -c "DISPLAY=:1 python3 << 'PYEOF'
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.enum.text import PP_ALIGN

prs = Presentation()

# --- Slide 1: Title Slide ---
slide1 = prs.slides.add_slide(prs.slide_layouts[0])
slide1.shapes.title.text = 'Global Renewable Energy Report 2023'
if len(slide1.placeholders) > 1:
    slide1.placeholders[1].text = 'Annual Solar PV Market Analysis\nPrepared by Sustainability Division'

# --- Slide 2: Content Slide ---
slide2 = prs.slides.add_slide(prs.slide_layouts[1])
slide2.shapes.title.text = 'Solar PV Market Overview'
tf = slide2.placeholders[1].text_frame
tf.text = 'Global solar PV capacity reached 1,070 GW in 2023'
p = tf.add_paragraph()
p.text = 'Year-over-year growth exceeded 25% globally'
p = tf.add_paragraph()
p.text = 'Asia Pacific dominates new installations'

# --- Slide 3: Blank slide with title text box only ---
# We use a blank layout and add a title manually to ensure no placeholder interferes
slide3 = prs.slides.add_slide(prs.slide_layouts[6])
title_box = slide3.shapes.add_textbox(Inches(0.5), Inches(0.5), Inches(9), Inches(1))
tf = title_box.text_frame
tf.text = 'Solar PV Capacity by Country'
for p in tf.paragraphs:
    p.font.size = Pt(32)
    p.font.bold = True

prs.save('$PRES_FILE')
PYEOF"

# Verify file creation
if [ ! -f "$PRES_FILE" ]; then
    echo "ERROR: Failed to create presentation file"
    exit 1
fi

# Record initial file state
stat -c %Y "$PRES_FILE" > /tmp/initial_file_mtime.txt
md5sum "$PRES_FILE" > /tmp/initial_file_hash.txt

# Open the file in LibreOffice Impress
echo "Opening presentation in LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$PRES_FILE' > /tmp/impress.log 2>&1 &"

# Wait for LibreOffice Impress window to appear
echo "Waiting for LibreOffice Impress to start..."
if wait_for_window "LibreOffice Impress\|renewable_energy" 60; then
    echo "Impress window detected"
else
    echo "ERROR: Impress window not found"
fi

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any startup dialogs (like "Tip of the Day")
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus the window explicitly
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take screenshot of initial state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="