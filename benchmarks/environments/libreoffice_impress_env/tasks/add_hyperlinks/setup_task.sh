#!/bin/bash
set -euo pipefail

echo "=== Setting up Add Hyperlinks Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define paths
PRES_DIR="/home/ga/Documents/Presentations"
PPTX_FILE="$PRES_DIR/community_resources.pptx"
ODP_FILE="$PRES_DIR/community_resources.odp"

# Clean up any previous run
rm -f "$PPTX_FILE" "$ODP_FILE" 2>/dev/null || true
mkdir -p "$PRES_DIR"
chown ga:ga "$PRES_DIR"

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create the initial presentation using python-pptx (available in env)
echo "Generating initial presentation content..."
cat > /tmp/generate_slides.py << 'PYEOF'
from pptx import Presentation
from pptx.util import Inches, Pt
import sys

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

def add_slide(title, content_items):
    slide = prs.slides.add_slide(prs.slide_layouts[1])
    slide.shapes.title.text = title
    tf = slide.placeholders[1].text_frame
    tf.clear()
    
    for i, item in enumerate(content_items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = item
        p.font.size = Pt(24)
        if i > 0:
            p.space_before = Pt(12)

# Slide 1
add_slide("Community Resource Guide", [
    "Housing Assistance",
    "Healthcare Services",
    "Employment Programs",
    "Education Resources"
])

# Slide 2
add_slide("Housing Assistance", [
    "Emergency shelter programs available through local agencies",
    "Section 8 Housing Choice Voucher applications open quarterly",
    "Habitat for Humanity homeownership opportunities",
    "Rental assistance grants for qualifying families"
])

# Slide 3
add_slide("Healthcare Services", [
    "Community health centers accepting sliding-scale payments",
    "Medicaid and CHIP enrollment assistance",
    "Mental health counseling and 24-hour crisis hotline",
    "Free vaccination clinics and cancer screening events"
])

# Slide 4
add_slide("Employment Programs", [
    "Job training and workforce development workshops",
    "Resume writing and interview preparation",
    "Career counseling and job placement services",
    "Small Business Development Center consulting"
])

# Slide 5
add_slide("Education Resources", [
    "Adult literacy and GED preparation classes",
    "English as a Second Language courses",
    "Scholarship and financial aid guidance",
    "After-school tutoring programs"
])

prs.save(sys.argv[1])
PYEOF

# Run generation script
python3 /tmp/generate_slides.py "$PPTX_FILE"

# Convert to ODP using LibreOffice headless
echo "Converting to ODP..."
libreoffice --headless --convert-to odp --outdir "$PRES_DIR" "$PPTX_FILE" > /dev/null 2>&1

# Ensure permissions
chown ga:ga "$ODP_FILE"

# Record initial file hash
md5sum "$ODP_FILE" | awk '{print $1}' > /tmp/initial_file_hash.txt

# Launch Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$ODP_FILE' > /tmp/impress.log 2>&1 &"

# Wait for window
wait_for_window "community_resources" 60 || wait_for_window "Impress" 30

# Maximize and focus
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Focusing window ID: $wid"
    focus_window "$wid"
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any potential recovery dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="