#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Architecture Diagram Task ==="

# Kill any existing LibreOffice instance
pkill -f soffice 2>/dev/null || true
sleep 2

# Clean up stale outputs BEFORE recording timestamp
PRES_DIR="/home/ga/Documents/Presentations"
TARGET_FILE="$PRES_DIR/platform_architecture.odp"
rm -f "$TARGET_FILE" 2>/dev/null || true
rm -f "$PRES_DIR/platform_architecture.pptx" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true
rm -f /tmp/initial_mtime.txt 2>/dev/null || true
rm -f /tmp/initial_file_hash.txt 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p "$PRES_DIR"

# Ensure python-pptx is installed (cache may not include pip packages)
pip3 install python-pptx 2>/dev/null || pip3 install --break-system-packages python-pptx 2>/dev/null || true

# Create starter presentation using python-pptx then convert to ODP
echo "Generating starter presentation..."
cat << 'PYEOF' | python3
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.enum.text import PP_ALIGN
import sys

try:
    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)

    # Slide 1: Title Slide
    slide_layout = prs.slide_layouts[0]
    slide1 = prs.slides.add_slide(slide_layout)
    slide1.shapes.title.text = "E-Commerce Platform Overview"
    slide1.placeholders[1].text = "Architecture & Design Document"

    # Slide 2: Blank slide with title text box
    slide_layout = prs.slide_layouts[6]  # Blank layout
    slide2 = prs.slides.add_slide(slide_layout)
    txBox = slide2.shapes.add_textbox(Inches(0.5), Inches(0.2), Inches(12), Inches(0.7))
    tf = txBox.text_frame
    p = tf.paragraphs[0]
    p.text = "System Architecture"
    p.font.size = Pt(28)
    p.font.bold = True
    p.alignment = PP_ALIGN.LEFT

    prs.save("/tmp/temp_architecture.pptx")
    print("Created PPTX starter file")
except Exception as e:
    print(f"Error creating starter file: {e}")
    sys.exit(1)
PYEOF

# Convert PPTX to ODP using headless LibreOffice
libreoffice --headless --convert-to odp --outdir "$PRES_DIR" /tmp/temp_architecture.pptx
mv "$PRES_DIR/temp_architecture.odp" "$TARGET_FILE"
rm -f /tmp/temp_architecture.pptx
chown ga:ga "$TARGET_FILE"

# Record initial file state for modification detection
stat -c %Y "$TARGET_FILE" > /tmp/initial_mtime.txt
md5sum "$TARGET_FILE" | awk '{print $1}' > /tmp/initial_file_hash.txt

# Suppress Tip of the Day and version notification before launching
LO_CONFIG="/home/ga/.config/libreoffice/4/user/registrymodifications.xcu"
if [ -f "$LO_CONFIG" ]; then
    # Add ShowTipOfTheDay=false if not already present
    if ! grep -q 'ShowTipOfTheDay' "$LO_CONFIG"; then
        sed -i 's|</oor:items>|<item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="ShowTipOfTheDay" oor:op="fuse"><value>false</value></prop></item>\n</oor:items>|' "$LO_CONFIG"
    fi
    # Set LastTipOfTheDayShown to far future
    sed -i 's|<prop oor:name="LastTipOfTheDayShown" oor:op="fuse"><value>[^<]*</value>|<prop oor:name="LastTipOfTheDayShown" oor:op="fuse"><value>32767</value>|' "$LO_CONFIG"
fi

# Launch LibreOffice Impress with the file
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$TARGET_FILE' > /tmp/impress_arch.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 20
wait_for_window "LibreOffice Impress" 60

# Maximize window
sleep 3
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz
    sleep 1
fi

# Dismiss any remaining startup dialogs
dismiss_dialogs
sleep 2
# Extra attempts to clear any remaining popups
safe_xdotool ga :1 key Escape
sleep 1
safe_xdotool ga :1 key Escape
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null \
    || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null \
    || true

echo "=== Task Setup Complete ==="
