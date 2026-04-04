#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Interactive Menu Task ==="

# Create directory
PRES_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$PRES_DIR"

# Generate the content using python-pptx (easier for rich content generation)
# then convert to ODP to ensure native Impress behavior
cat << 'PYEOF' > /tmp/gen_presentation.py
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor

prs = Presentation()

# Define slide content
slides_content = [
    ("Welcome to Acme Corp", "New Hire Orientation Kiosk\nPlease select a topic to begin."),
    ("Our History", "Founded in 1985\nOriginal HQ in Garage\nIPO in 1999"),
    ("Founding Story", "It began with a simple idea...\n(Detailed text would go here)"),
    ("Employee Benefits", "We take care of our team.\nSelect a sub-topic to learn more."),
    ("Health & Dental", "Comprehensive coverage\n$0 deductible plans available"),
    ("Company Policies", "Rules of the road\nImportant compliance information"),
    ("Remote Work Policy", "Hybrid model is standard\n3 days in office expected"),
    ("Contact Us", "HR Department: ext 500\nIT Support: ext 505")
]

for title, content in slides_content:
    # Use Title and Content layout
    slide_layout = prs.slide_layouts[1]
    slide = prs.slides.add_slide(slide_layout)
    
    # Set title
    slide.shapes.title.text = title
    
    # Set content
    if slide.placeholders[1].has_text_frame:
        tf = slide.placeholders[1].text_frame
        tf.text = content

# Save as PPTX first
prs.save("/tmp/temp_kiosk.pptx")
PYEOF

# Run generation
python3 /tmp/gen_presentation.py

# Convert to ODP using LibreOffice headless
echo "Converting to ODP format..."
libreoffice --headless --convert-to odp --outdir "$PRES_DIR" /tmp/temp_kiosk.pptx

# Rename to final start filename
mv "$PRES_DIR/temp_kiosk.odp" "$PRES_DIR/orientation_kiosk.odp"
chown ga:ga "$PRES_DIR/orientation_kiosk.odp"

# Clean up
rm /tmp/gen_presentation.py /tmp/temp_kiosk.pptx

# Launch Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress $PRES_DIR/orientation_kiosk.odp > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 60

# Maximize and focus
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Ensure optimized view (Normal view)
    safe_xdotool ga :1 key Escape
    safe_xdotool ga :1 key Escape
fi

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="
echo "Presentation created at: $PRES_DIR/orientation_kiosk.odp"