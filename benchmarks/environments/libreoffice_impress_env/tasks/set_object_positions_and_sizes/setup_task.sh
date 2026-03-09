#!/bin/bash
set -e
echo "=== Setting up set_object_positions_and_sizes task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directory exists
PRES_DIR="/home/ga/Documents/Presentations"
mkdir -p "$PRES_DIR"
chown ga:ga "$PRES_DIR"

# Generate the initial "messy" presentation using python-pptx (installed in env)
echo "Generating initial presentation..."
python3 << 'PYEOF'
from pptx import Presentation
from pptx.util import Cm, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
import json
import os

prs = Presentation()

# Slide 1: Title
slide_layout_title = prs.slide_layouts[0]
slide1 = prs.slides.add_slide(slide_layout_title)
slide1.shapes.title.text = "IC Component Layout"
slide1.placeholders[1].text = "Design Review — Q4 2024\nMicrosystems Engineering Team"

# Slide 2: Messy Block Diagram
slide_layout_blank = prs.slide_layouts[6]
slide2 = prs.slides.add_slide(slide_layout_blank)

# Title box
txBox = slide2.shapes.add_textbox(Cm(1.0), Cm(0.5), Cm(23.0), Cm(2.0))
tf = txBox.text_frame
tf.text = "Component Block Diagram"
tf.paragraphs[0].font.size = Pt(28)
tf.paragraphs[0].font.bold = True

# Helper to create styled shape
def add_block(text, x, y, w, h, color):
    shape = slide2.shapes.add_shape(1, Cm(x), Cm(y), Cm(w), Cm(h)) # 1 = msoShapeRectangle
    shape.fill.solid()
    shape.fill.fore_color.rgb = color
    shape.text_frame.text = text
    p = shape.text_frame.paragraphs[0]
    p.font.size = Pt(16)
    p.font.color.rgb = RGBColor(255, 255, 255)
    p.font.bold = True
    p.alignment = PP_ALIGN.CENTER
    shape.name = text # Set name for easier identification
    return shape

# Add messy shapes (overlapping, wrong sizes)
# Target: Y=7.0, W=6.5, H=4.5
# CPU Core (Blue)
s1 = add_block("CPU Core", 3.0, 2.5, 4.0, 6.5, RGBColor(65, 105, 225))
# Memory Controller (Green)
s2 = add_block("Memory Controller", 6.0, 10.0, 9.0, 3.0, RGBColor(46, 139, 87))
# I/O Interface (Orange)
s3 = add_block("I/O Interface", 16.0, 4.0, 5.5, 8.0, RGBColor(218, 112, 38))

# Save
output_path = "/home/ga/Documents/Presentations/chip_layout.pptx"
prs.save(output_path)
print(f"Presentation saved to {output_path}")

# Record initial state for anti-gaming
initial_state = {
    "CPU Core": {"x": 3.0, "y": 2.5, "w": 4.0, "h": 6.5},
    "Memory Controller": {"x": 6.0, "y": 10.0, "w": 9.0, "h": 3.0},
    "I/O Interface": {"x": 16.0, "y": 4.0, "w": 5.5, "h": 8.0}
}
with open("/tmp/initial_shape_state.json", "w") as f:
    json.dump(initial_state, f)

os.chmod(output_path, 0o666)
PYEOF

chown ga:ga /home/ga/Documents/Presentations/chip_layout.pptx

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/chip_layout.pptx > /tmp/impress_launch.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Impress" 60 || wait_for_window "chip_layout" 60

# Maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Maximizing window $wid..."
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid"
    
    # Dismiss any startup dialogs (like "Tip of the Day")
    sleep 2
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    
    # Navigate to Slide 2 so agent sees the mess
    sleep 1
    DISPLAY=:1 xdotool key Page_Down 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="