#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Lab Report Captions Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Document directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 1. Generate Dummy Images (BMP format using simple Python to avoid deps)
# We need 3 distinct images: Pie, Bar, Map
echo "Generating task images..."
python3 -c "
import struct

def write_bmp(filename, width, height, color):
    # Simple BMP header writing
    # File Header (14 bytes)
    # Info Header (40 bytes)
    padding = (4 - (width * 3) % 4) % 4
    filesize = 14 + 40 + (width * 3 + padding) * height
    
    with open(filename, 'wb') as f:
        # BITMAPFILEHEADER
        f.write(b'BM')
        f.write(struct.pack('<I', filesize))
        f.write(b'\x00\x00') # Reserved
        f.write(b'\x00\x00') # Reserved
        f.write(struct.pack('<I', 54)) # Offset
        
        # BITMAPINFOHEADER
        f.write(struct.pack('<I', 40)) # Size
        f.write(struct.pack('<i', width))
        f.write(struct.pack('<i', height))
        f.write(struct.pack('<H', 1)) # Planes
        f.write(struct.pack('<H', 24)) # Bit count
        f.write(struct.pack('<I', 0)) # Compression
        f.write(struct.pack('<I', 0)) # Size Image
        f.write(struct.pack('<i', 0)) # X pixels/m
        f.write(struct.pack('<i', 0)) # Y pixels/m
        f.write(struct.pack('<I', 0)) # Colors used
        f.write(struct.pack('<I', 0)) # Colors important
        
        # Pixel Data (BGR format)
        row = (bytes([color[2], color[1], color[0]]) * width) + (b'\x00' * padding)
        for _ in range(height):
            f.write(row)

# Blue image for Pie Chart placeholder
write_bmp('/tmp/chart_pie.bmp', 400, 300, (100, 149, 237)) 
# Green image for Bar Chart placeholder
write_bmp('/tmp/chart_bar.bmp', 400, 300, (60, 179, 113))
# Red/Tan image for Map placeholder
write_bmp('/tmp/map_loc.bmp', 400, 300, (210, 180, 140))
"

# 2. Generate the Draft DOCX
echo "Generating draft document..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Title
title = doc.add_paragraph("Soil Analysis Report: Site 42-B")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = title.runs[0]
run.bold = True
run.font.size = Pt(16)

doc.add_paragraph("Prepared by: Environmental Services Ltd.").alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph("Date: October 12, 2024").alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph("")

# Section 1
doc.add_heading("1. Soil Composition", level=1)
doc.add_paragraph(
    "The initial breakdown of soil components reveals a high percentage of "
    "clay mixed with silt. As shown in [REF_FIG_COMP], the primary constituent "
    "is clay (45%), followed by silt (35%) and sand (20%). This composition "
    "suggests poor drainage characteristics for the northern sector."
)

# Image 1 (Pie)
doc.add_picture("/tmp/chart_pie.bmp", width=Inches(3.0))
last_p = doc.paragraphs[-1]
last_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph("") # Spacing

# Section 2
doc.add_heading("2. Chemical Properties", level=1)
doc.add_paragraph(
    "Chemical analysis focused on pH levels and nitrogen content. "
    "The results indicated varying acidity across the three main test zones. "
    "Refer to [REF_FIG_PH] for a comparison of pH levels by zone. Zone A "
    "exhibited the highest acidity, requiring lime treatment before planting."
)

# Image 2 (Bar)
doc.add_picture("/tmp/chart_bar.bmp", width=Inches(3.0))
last_p = doc.paragraphs[-1]
last_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph("")

# Section 3
doc.add_heading("3. Sampling Locations", level=1)
doc.add_paragraph(
    "Samples were collected from 15 distinct points distributed across the "
    "site grid. The distribution of these points is visualized in [REF_FIG_MAP], "
    "which highlights the concentration of samples near the riverbed boundary."
)

# Image 3 (Map)
doc.add_picture("/tmp/map_loc.bmp", width=Inches(3.0))
last_p = doc.paragraphs[-1]
last_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph("")

# Section 4
doc.add_heading("4. Conclusion", level=1)
doc.add_paragraph(
    "Based on the data presented in the figures above, we recommend a soil "
    "amendment plan focusing on pH neutralization and drainage improvement."
)

doc.add_paragraph("")
doc.add_heading("List of Figures", level=1)
doc.add_paragraph("(Insert Table of Figures here)")

doc.save("/home/ga/Documents/soil_analysis_draft.docx")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/soil_analysis_draft.docx
chmod 666 /home/ga/Documents/soil_analysis_draft.docx

# 3. Launch Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/soil_analysis_draft.docx > /tmp/writer.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "soil_analysis_draft" 30

# Maximize
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="