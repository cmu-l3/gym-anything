#!/bin/bash
# setup_task.sh — Mixed Column Layout Flyer

source /workspace/scripts/task_utils.sh

echo "=== Setting up Real Estate Flyer Task ==="

# 1. Create directories
sudo -u ga mkdir -p /home/ga/Documents/images

# 2. Generate the placeholder "Luxury Home" image
# Using ImageMagick to create a compelling looking placeholder
if command -v convert >/dev/null 2>&1; then
    echo "Generating placeholder image..."
    convert -size 1024x768 gradient:skyblue-wheat \
        -fill white -stroke black -strokewidth 2 \
        -font DejaVu-Sans-Bold -pointsize 72 -gravity center \
        -draw "text 0,0 'LUXURY HOME\nFOR SALE'" \
        /home/ga/Documents/images/luxury_home.jpg
else
    # Fallback if ImageMagick missing (unlikely in this env)
    echo "Downloading placeholder image..."
    curl -L -o /home/ga/Documents/images/luxury_home.jpg "https://via.placeholder.com/1024x768.png?text=Luxury+Home"
fi

# Ensure correct permissions
chown ga:ga /home/ga/Documents/images/luxury_home.jpg
chmod 644 /home/ga/Documents/images/luxury_home.jpg

# 3. Create the Draft Document with python-docx
# We use python-docx to ensure a clean "Normal" style starting state
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# Raw text content - flat structure
doc.add_paragraph("OPEN HOUSE - SUNDAY")
doc.add_paragraph("123 Maple Drive, Springfield, IL")
doc.add_paragraph("") # Space for image

doc.add_paragraph("Property Description")
doc.add_paragraph(
    "Nestled in the heart of the historic district, this charming 3-bedroom, 2-bathroom "
    "Victorian home offers the perfect blend of classic elegance and modern convenience. "
    "Recently renovated, the property features a gourmet kitchen with stainless steel "
    "appliances, original hardwood floors throughout, and a spacious backyard perfect "
    "for entertaining. The master suite includes a walk-in closet and a spa-like bath. "
    "Walking distance to schools, parks, and downtown shopping."
)

doc.add_paragraph("Key Features:")
doc.add_paragraph("Granite countertops and custom cabinetry")
doc.add_paragraph("Original oak hardwood floors (refinished 2023)")
doc.add_paragraph("New HVAC system and energy-efficient windows")
doc.add_paragraph("Detached 2-car garage with workshop")
doc.add_paragraph("Finished basement with separate entrance")
doc.add_paragraph("Smart home security system installed")

doc.save("/home/ga/Documents/property_draft.docx")
PYEOF

chown ga:ga /home/ga/Documents/property_draft.docx
chmod 666 /home/ga/Documents/property_draft.docx

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/property_draft.docx > /tmp/writer.log 2>&1 &"

# 6. Wait for window and maximize
if wait_for_window "LibreOffice Writer" 60; then
    WID=$(get_writer_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    fi
else
    echo "WARNING: LibreOffice window not detected"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="