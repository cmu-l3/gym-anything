#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Venn Diagram Task ==="

# 1. Create directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# 2. Generate Initial Presentation using Python
# We use python-pptx to generate content, then convert to ODP
# This ensures a clean, realistic starting state
echo "Generating initial presentation content..."
cat << 'PYEOF' > /tmp/generate_pres.py
import os
import subprocess
from pptx import Presentation
from pptx.util import Inches

def create_initial_presentation():
    prs = Presentation()
    
    # Slide 1: Title
    slide1 = prs.slides.add_slide(prs.slide_layouts[0])
    slide1.shapes.title.text = "2024 Sustainability Strategy Report"
    slide1.placeholders[1].text = "Prepared for the Board of Directors — Q4 Review"

    # Slide 2: Key Achievements
    slide2 = prs.slides.add_slide(prs.slide_layouts[1])
    slide2.shapes.title.text = "Key Achievements This Year"
    tf = slide2.placeholders[1].text_frame
    tf.text = "Reduced Scope 1 & 2 carbon emissions by 18% vs. 2023 baseline"
    p = tf.add_paragraph()
    p.text = "Achieved 42% renewable energy procurement across all facilities"
    p = tf.add_paragraph()
    p.text = "Launched supplier sustainability scorecard covering 85% of tier-1 vendors"
    p = tf.add_paragraph()
    p.text = "Published first TCFD-aligned climate risk disclosure"

    # Slide 3: Strategic Priorities
    slide3 = prs.slides.add_slide(prs.slide_layouts[1])
    slide3.shapes.title.text = "Strategic Priorities for 2025"
    tf3 = slide3.placeholders[1].text_frame
    tf3.text = "Set science-based targets validated by SBTi for Scope 3 emissions"
    p = tf3.add_paragraph()
    p.text = "Implement circular economy program targeting 60% waste diversion"
    p = tf3.add_paragraph()
    p.text = "Expand DEI reporting with intersectional workforce analytics"

    pptx_path = "/tmp/sustainability_report.pptx"
    prs.save(pptx_path)
    print(f"Created PPTX at {pptx_path}")

if __name__ == "__main__":
    create_initial_presentation()
PYEOF

# Run generation script
python3 /tmp/generate_pres.py

# Convert to ODP using LibreOffice headless
echo "Converting to ODP..."
libreoffice --headless --convert-to odp --outdir /home/ga/Documents/Presentations /tmp/sustainability_report.pptx

TARGET_FILE="/home/ga/Documents/Presentations/sustainability_report.odp"
sudo chown ga:ga "$TARGET_FILE"

# 3. Record Initial State for Anti-Gaming
echo "Recording initial state..."
date +%s > /tmp/task_start_time.txt
md5sum "$TARGET_FILE" | awk '{print $1}' > /tmp/initial_file_hash.txt
# Get initial slide count (using python one-liner with odfpy)
python3 -c "from odf import opendocument, draw; doc=opendocument.load('$TARGET_FILE'); print(len(doc.getElementsByType(draw.Page)))" > /tmp/initial_slide_count.txt

# 4. Launch Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$TARGET_FILE' > /tmp/impress.log 2>&1 &"

# 5. Wait for application
wait_for_window "LibreOffice Impress" 30 || wait_for_window "sustainability" 30

# 6. Configure Window (Maximize and Focus)
WID=$(get_impress_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
    # Maximize
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    sleep 1
    # Ensure focus again
    focus_window "$WID"
fi

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target File: $TARGET_FILE"