#!/bin/bash
set -euo pipefail

echo "=== Setting up Configure Kiosk Slideshow Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure target directory exists
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 1

# Create the initial presentation using python-pptx (installed in env)
# We generate a PPTX first to ensure rich content, then convert to ODP
cat > /tmp/create_presentation.py << 'PYEOF'
#!/usr/bin/env python3
"""Create a community center kiosk presentation using python-pptx"""
import sys
try:
    from pptx import Presentation
    from pptx.util import Inches, Pt
except ImportError:
    print("python-pptx not found")
    sys.exit(1)

prs = Presentation()
# Widescreen
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

slides_content = [
    {
        "title": "Welcome to Riverdale Community Center",
        "bullets": ["Serving Our Community Since 1987", "Open 7 Days a Week", "Programs for All Ages"]
    },
    {
        "title": "Youth Programs",
        "bullets": ["After-School Tutoring — Grades K through 12", "Summer Day Camp — Ages 6 to 14", "Teen Leadership Academy — Ages 13 to 18"]
    },
    {
        "title": "Adult Education",
        "bullets": ["ESL Classes — Beginner to Advanced", "Computer Literacy Workshops", "Financial Planning Seminars"]
    },
    {
        "title": "Senior Services",
        "bullets": ["Daily Meal Program", "Weekly Health Screenings", "Social Activities and Outings"]
    },
    {
        "title": "Fitness and Recreation",
        "bullets": ["Group Fitness Classes", "Swimming Pool and Aquatics", "Basketball and Tennis Courts"]
    },
    {
        "title": "Visit Us Today",
        "bullets": ["450 Oak Street, Riverdale", "Open Mon-Sat 7AM-9PM", "Phone: (555) 234-5678"]
    }
]

for i, content in enumerate(slides_content):
    if i == 0:
        layout = prs.slide_layouts[0]  # Title slide
    else:
        layout = prs.slide_layouts[1]  # Title and content

    slide = prs.slides.add_slide(layout)

    # Set title
    if slide.shapes.title:
        slide.shapes.title.text = content["title"]

    # Set bullets
    for shape in slide.placeholders:
        if shape.placeholder_format.idx == 1:
            tf = shape.text_frame
            tf.clear()
            for bullet in content["bullets"]:
                p = tf.add_paragraph()
                p.text = bullet
                p.level = 0

output_path = "/home/ga/Documents/Presentations/community_kiosk.pptx"
prs.save(output_path)
print(f"Created presentation at {output_path}")
PYEOF

echo "Generating initial presentation content..."
python3 /tmp/create_presentation.py

# Convert PPTX to ODP using LibreOffice headless
# This ensures a clean, native ODP file for the task
echo "Converting to ODP format..."
cd /home/ga/Documents/Presentations/
libreoffice --headless --convert-to odp community_kiosk.pptx > /dev/null 2>&1
sleep 2

# Verify ODP creation
if [ ! -f "community_kiosk.odp" ]; then
    echo "ERROR: ODP conversion failed"
    # Fallback: just use empty if conversion fails (should not happen in this env)
    cp community_kiosk.pptx community_kiosk.odp
fi

# Clean up intermediate file
rm community_kiosk.pptx

# Set ownership
chown ga:ga community_kiosk.odp

# Calculate initial hash for anti-gaming
md5sum community_kiosk.odp | awk '{print $1}' > /tmp/initial_file_hash.txt

# Launch LibreOffice Impress with the file
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/community_kiosk.odp > /tmp/impress.log 2>&1 &"

# Wait for process
wait_for_process "soffice" 20

# Wait for window
wait_for_window "LibreOffice Impress" 60

# Maximize and focus
WID=$(get_impress_window_id)
if [ -n "$WID" ]; then
    echo "Focusing window ID: $WID"
    focus_window "$WID"
    sleep 1
    # Ensure maximized
    DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any potential recovery dialogs or startup tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="