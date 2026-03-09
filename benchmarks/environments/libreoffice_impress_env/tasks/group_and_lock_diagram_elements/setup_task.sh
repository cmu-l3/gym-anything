#!/bin/bash
set -e
echo "=== Setting up Group and Lock Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Define paths
TASK_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$TASK_DIR"
SOURCE_FILE="$TASK_DIR/cell_biology_quiz.pptx"

echo "Generating input presentation..."

# Generate the input PPTX using python-pptx
# We use python3 from the system which has python-pptx installed per env spec
python3 -c "
import sys
try:
    from pptx import Presentation
    from pptx.util import Inches, Pt
    from pptx.enum.shapes import MSO_SHAPE
    from pptx.dml.color import RGBColor
except ImportError:
    print('Error: python-pptx not found')
    sys.exit(1)

prs = Presentation()
slide_layout = prs.slide_layouts[6] # Blank
slide = prs.slides.add_slide(slide_layout)

# 1. Main Cell Body (Blue Circle) - Left Side
# shape_id 2
cell = slide.shapes.add_shape(MSO_SHAPE.OVAL, Inches(1), Inches(2), Inches(4), Inches(4))
cell.fill.solid()
cell.fill.fore_color.rgb = RGBColor(100, 149, 237) # Cornflower Blue
cell.line.color.rgb = RGBColor(0, 0, 139)
cell.name = 'Cell Membrane'

# 2. Nucleus (Purple Circle) - Inside Cell
# shape_id 3
nucleus = slide.shapes.add_shape(MSO_SHAPE.OVAL, Inches(2.5), Inches(3), Inches(1.2), Inches(1.2))
nucleus.fill.solid()
nucleus.fill.fore_color.rgb = RGBColor(147, 112, 219) # Medium Purple
nucleus.name = 'Nucleus'

# 3. Mitochondria 1 (Orange Oval)
# shape_id 4
mito1 = slide.shapes.add_shape(MSO_SHAPE.OVAL, Inches(1.5), Inches(2.5), Inches(0.8), Inches(0.4))
mito1.fill.solid()
mito1.fill.fore_color.rgb = RGBColor(255, 165, 0) # Orange
mito1.rotation = 45
mito1.name = 'Mitochondria 1'

# 4. Mitochondria 2 (Orange Oval)
# shape_id 5
mito2 = slide.shapes.add_shape(MSO_SHAPE.OVAL, Inches(3.5), Inches(4.5), Inches(0.8), Inches(0.4))
mito2.fill.solid()
mito2.fill.fore_color.rgb = RGBColor(255, 165, 0) # Orange
mito2.rotation = -30
mito2.name = 'Mitochondria 2'

# 5. Labels - Right Side (Separate)
labels = [
    ('Cell Membrane', 2.5),
    ('Nucleus', 3.5),
    ('Mitochondria', 4.5),
    ('Cytoplasm', 5.5)
]

for text, top_inch in labels:
    txBox = slide.shapes.add_textbox(Inches(5.5), Inches(top_inch), Inches(2.5), Inches(0.5))
    tf = txBox.text_frame
    tf.text = text
    p = tf.paragraphs[0]
    p.font.size = Pt(18)
    p.font.bold = True
    p.font.name = 'Liberation Sans'

prs.save('$SOURCE_FILE')
print(f'Created {SOURCE_FILE}')
"

# Set permissions
chown ga:ga "$SOURCE_FILE"

# Start LibreOffice Impress
echo "Starting LibreOffice Impress..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --impress '$SOURCE_FILE' > /tmp/impress_task.log 2>&1 &"
fi

# Wait for window
wait_for_window "LibreOffice Impress" 60

# Get window ID
wid=$(get_impress_window_id)

if [ -n "$wid" ]; then
    echo "Configuring window..."
    focus_window "$wid"
    
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Click to ensure focus on the slide pane/edit area (center of screen)
    safe_xdotool ga :1 mousemove 960 540 click 1
    sleep 0.5
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="