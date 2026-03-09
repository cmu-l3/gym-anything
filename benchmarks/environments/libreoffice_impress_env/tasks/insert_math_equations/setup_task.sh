#!/bin/bash
set -e
echo "=== Setting up insert_math_equations task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Ensure directory exists
mkdir -p /home/ga/Documents/Presentations

# Generate the initial presentation using python-pptx (more reliable programmatic generation)
# Then convert to ODP
cat > /tmp/create_physics_slides.py << 'PYEOF'
from pptx import Presentation
from pptx.util import Inches, Pt

prs = Presentation()

# Slide 1: Title
slide1 = prs.slides.add_slide(prs.slide_layouts[0])
slide1.shapes.title.text = "Introduction to Classical Mechanics"
slide1.placeholders[1].text = "Fundamental Equations of Physics\nPHYS 101 - Lecture 7"

# Slide 2: Newton's Second Law
slide2 = prs.slides.add_slide(prs.slide_layouts[1])
slide2.shapes.title.text = "Newton's Second Law"
tf = slide2.placeholders[1].text_frame
tf.text = "The net force on an object equals the product of its mass and acceleration."
p = tf.add_paragraph()
p.text = "This fundamental law governs the motion of all macroscopic objects."
p = tf.add_paragraph()
p.text = ""
p = tf.add_paragraph()
p.text = "[Insert F = ma equation here]"

# Slide 3: Kinetic Energy
slide3 = prs.slides.add_slide(prs.slide_layouts[1])
slide3.shapes.title.text = "Kinetic Energy"
tf = slide3.placeholders[1].text_frame
tf.text = "The kinetic energy of a moving object is proportional to its mass and the square of its velocity."
p = tf.add_paragraph()
p.text = "It represents the energy of motion."
p = tf.add_paragraph()
p.text = ""
p = tf.add_paragraph()
p.text = "[Insert Kinetic Energy equation here]"

# Slide 4: Mass-Energy Equivalence
slide4 = prs.slides.add_slide(prs.slide_layouts[1])
slide4.shapes.title.text = "Mass-Energy Equivalence"
tf = slide4.placeholders[1].text_frame
tf.text = "Einstein's famous equation shows that mass and energy are interchangeable."
p = tf.add_paragraph()
p.text = "A small amount of mass corresponds to an enormous amount of energy."
p = tf.add_paragraph()
p.text = ""
p = tf.add_paragraph()
p.text = "[Insert E = mc^2 equation here]"

# Slide 5: Summary
slide5 = prs.slides.add_slide(prs.slide_layouts[1])
slide5.shapes.title.text = "Summary and Questions"
tf = slide5.placeholders[1].text_frame
tf.text = "These three equations form cornerstones of physics."
p = tf.add_paragraph()
p.text = "Questions?"

prs.save("/tmp/classical_mechanics.pptx")
PYEOF

echo "Generating content..."
python3 /tmp/create_physics_slides.py

echo "Converting to ODP..."
libreoffice --headless --convert-to odp --outdir /home/ga/Documents/Presentations/ /tmp/classical_mechanics.pptx

# Set permissions
chown -R ga:ga /home/ga/Documents/Presentations

# Record initial file state
TARGET_FILE="/home/ga/Documents/Presentations/classical_mechanics.odp"
if [ -f "$TARGET_FILE" ]; then
    stat -c %s "$TARGET_FILE" > /tmp/initial_file_size.txt
    stat -c %Y "$TARGET_FILE" > /tmp/initial_file_mtime.txt
else
    echo "ERROR: Failed to create initial presentation"
    exit 1
fi

# Launch Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress $TARGET_FILE > /dev/null 2>&1 &"

# Wait for window
wait_for_window "classical_mechanics" 60 || wait_for_window "Impress" 60

# Maximize and focus
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any potential "Tip of the Day" dialogs
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="