#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Soil Report Image Insertion Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
sudo -u ga mkdir -p /home/ga/Documents/images

# 1. Generate realistic "dummy" images using ImageMagick
# We generate them to ensure they exist and are valid JPEGs without external dependencies
echo "Generating task images..."

# Figure 1: Landscape (Green/Brown)
convert -size 800x600 gradient:DarkOliveGreen-SaddleBrown \
    -pointsize 30 -fill white -gravity center -annotate +0+0 "Figure 1: Site Overview\nTallahatchie County" \
    /home/ga/Documents/images/fig1_site_overview.jpg

# Figure 2: Soil Profile (Vertical, multi-colored)
convert -size 400x800 -define gradient:direction=north gradient:black-orange \
    -pointsize 30 -fill white -gravity center -annotate +0+0 "Figure 2: Soil Profile\nSharkey Clay" \
    /home/ga/Documents/images/fig2_soil_profile.jpg

# Figure 3: Sampling Equipment (Grey/Blue)
convert -size 800x600 gradient:gray-silver \
    -pointsize 30 -fill black -gravity center -annotate +0+0 "Figure 3: Sampling\nAuger T-14" \
    /home/ga/Documents/images/fig3_sampling.jpg

# Set permissions
chown -R ga:ga /home/ga/Documents/images

# 2. Create the draft document with placeholders using python-docx
echo "Creating draft document..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Title
title = doc.add_paragraph("Soil Survey Manuscript — Tallahatchie County, Mississippi")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in title.runs:
    run.bold = True
    run.font.size = Pt(16)

doc.add_paragraph("")

# Section 1
doc.add_heading("1. General Description of the Survey Area", level=1)
doc.add_paragraph(
    "Tallahatchie County is located in the northwestern part of Mississippi, "
    "within the Mississippi Alluvial Plain. The county has a total area of 652 "
    "square miles, of which 644 square miles is land and 8 square miles is water. "
    "The climate is characterized by hot, humid summers and mild winters, with "
    "an average annual precipitation of 53 inches. The landscape is dominated by "
    "broad, level floodplains formed by the meandering of the Tallahatchie River."
)

# Placeholder 1
p = doc.add_paragraph("[INSERT FIGURE 1 HERE]")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in p.runs:
    run.bold = True
    run.font.color.rgb = None  # Default color

doc.add_paragraph(
    "The vegetation in the survey area consists primarily of bottomland hardwood "
    "forests and cultivated cropland. Major crops include soybeans, cotton, and "
    "corn. The relief is generally low, with elevations ranging from 130 to 170 "
    "feet above sea level."
)

# Section 2
doc.add_heading("2. Morphological Description of Dominant Soils", level=1)
doc.add_paragraph(
    "The Sharkey series consists of very deep, poorly drained, very slowly permeable "
    "soils that formed in clayey alluvium. These soils are on low terraces and "
    "flood plains of the Mississippi River and its tributaries. Slope ranges from "
    "0 to 2 percent. Sharkey soils are extensive in the county and are of major "
    "agricultural importance."
)

# Placeholder 2
p = doc.add_paragraph("[INSERT FIGURE 2 HERE]")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in p.runs:
    run.bold = True

doc.add_paragraph(
    "A typical pedon of Sharkey clay, 0 to 1 percent slopes, is located 2 miles "
    "south of Charleston. The Ap horizon (0–15 cm) is dark gray clay with strong "
    "fine granular structure. The Bg horizon (15–85 cm) is gray clay with "
    "distinct yellowish brown mottles and strong medium subangular blocky structure. "
    "Slickensides are common in the Bss horizon (85–150 cm), indicating significant "
    "shrink-swell potential (vertic properties) associated with high montmorillonite content."
)

# Section 3
doc.add_heading("3. Field Methods and Sampling Procedures", level=1)
doc.add_paragraph(
    "Soil samples were collected from representative pedons using a bucket auger "
    "and sharpshooter shovel. Transects were established at 100-meter intervals "
    "across map units to verify soil composition and boundary placement."
)

# Placeholder 3
p = doc.add_paragraph("[INSERT FIGURE 3 HERE]")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in p.runs:
    run.bold = True

doc.add_paragraph(
    "At each sampling point, soil morphology was described according to the Field "
    "Book for Describing and Sampling Soils (Version 3.0). Horizon depth, color, "
    "texture, structure, and redoximorphic features were recorded. Samples for "
    "laboratory analysis were placed in sealed polyethylene bags and transported "
    "to the USDA-NRCS Soil Survey Laboratory."
)

doc.save("/home/ga/Documents/soil_survey_draft.docx")
print("Draft document created successfully.")
PYEOF

chown ga:ga /home/ga/Documents/soil_survey_draft.docx

# 3. Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/soil_survey_draft.docx > /tmp/writer_task.log 2>&1 &"

# Wait for Writer to start
if ! wait_for_process "soffice" 20; then
    echo "ERROR: LibreOffice failed to start"
    exit 1
fi

# Wait for window
if ! wait_for_window "LibreOffice Writer" 60; then
    # Try searching for document name in title
    wait_for_window "soil_survey" 30 || true
fi

# Focus and maximize
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss potential "Tip of the Day" or recovery dialogs
    safe_xdotool ga :1 key Escape
    sleep 0.5
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Insert 3 images and captions into soil_survey_draft.docx"
echo "Images located in: /home/ga/Documents/images/"