#!/bin/bash
set -e
echo "=== Setting up Apply Drop Shadows Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Generate the starting presentation using python-pptx (then convert to ODP)
# This ensures a clean, controllable starting state with NO shadows
echo "Generating starting presentation..."
cat << 'PYEOF' > /tmp/create_pres.py
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
import sys

try:
    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)

    # Slide 1: Title
    slide1 = prs.slides.add_slide(prs.slide_layouts[0])
    slide1.shapes.title.text = "Q4 Quarterly Business Review"
    slide1.placeholders[1].text = "Sales Division — FY2024"

    # Slide 2: Product Comparison
    slide2 = prs.slides.add_slide(prs.slide_layouts[6]) # Blank
    
    # Title
    txBox = slide2.shapes.add_textbox(Inches(0.5), Inches(0.3), Inches(12), Inches(0.8))
    tf = txBox.text_frame
    tf.text = "Product Tier Comparison"
    tf.paragraphs[0].font.size = Pt(28)
    tf.paragraphs[0].font.bold = True
    
    tiers = [
        {"name": "Starter", "price": "$9/mo", "color": RGBColor(0xAE, 0xC6, 0xCF)},
        {"name": "Basic", "price": "$29/mo", "color": RGBColor(0xB2, 0xD8, 0xB2)},
        {"name": "Pro", "price": "$79/mo", "color": RGBColor(0xFD, 0xFD, 0x96)},
        {"name": "Enterprise", "price": "$199/mo", "color": RGBColor(0xFF, 0xB3, 0x47)},
        {"name": "Ultimate", "price": "$499/mo", "color": RGBColor(0xB1, 0x9C, 0xD9)},
    ]

    left_start = Inches(0.5)
    width = Inches(2.3)
    height = Inches(4.5)
    gap = Inches(0.25)
    top = Inches(1.5)

    for i, tier in enumerate(tiers):
        left = left_start + i * (width + gap)
        shape = slide2.shapes.add_shape(1, left, top, width, height) # MSO_SHAPE.RECTANGLE
        shape.fill.solid()
        shape.fill.fore_color.rgb = tier["color"]
        shape.line.color.rgb = RGBColor(0x99, 0x99, 0x99)
        shape.shadow.inherit = False # Explicitly disable shadow
        
        tf = shape.text_frame
        p = tf.paragraphs[0]
        p.text = tier["name"]
        p.font.size = Pt(20)
        p.font.bold = True
        p.alignment = PP_ALIGN.CENTER
        
        p2 = tf.add_paragraph()
        p2.text = tier["price"]
        p2.font.size = Pt(24)
        p2.alignment = PP_ALIGN.CENTER

    # Slide 3: Summary
    slide3 = prs.slides.add_slide(prs.slide_layouts[1])
    slide3.shapes.title.text = "Summary & Next Steps"
    slide3.placeholders[1].text = "Review completed.\nNext steps TBD."

    prs.save("/tmp/quarterly_review.pptx")
    print("PPTX generated successfully")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
PYEOF

# Run generation script
python3 /tmp/create_pres.py

# Convert to ODP
echo "Converting to ODP..."
libreoffice --headless --convert-to odp --outdir /home/ga/Documents/Presentations /tmp/quarterly_review.pptx

# Set permissions and cleanup
chown ga:ga /home/ga/Documents/Presentations/quarterly_review.odp
rm -f /tmp/quarterly_review.pptx /tmp/create_pres.py

# Hash the original file for comparison
md5sum /home/ga/Documents/Presentations/quarterly_review.odp > /tmp/original_file.md5

# Launch Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/quarterly_review.odp > /tmp/impress.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Impress" 30 || wait_for_window "quarterly_review" 30

# Maximize
DISPLAY=:1 wmctrl -r "LibreOffice Impress" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Navigate to Slide 2 to help the agent start
sleep 2
DISPLAY=:1 xdotool key Page_Down
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="