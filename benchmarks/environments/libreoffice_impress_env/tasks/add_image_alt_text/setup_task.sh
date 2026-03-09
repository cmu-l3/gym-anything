#!/bin/bash
set -euo pipefail
echo "=== Setting up Add Image Alt Text Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create directories
sudo -u ga mkdir -p /home/ga/Documents/Presentations
sudo -u ga mkdir -p /tmp/chart_images

# Generate presentation with chart images
# We use Python with Pillow (which is installed) instead of matplotlib to avoid dependency issues
cat > /tmp/create_accessible_pres.py << 'PYEOF'
import os
import random
from PIL import Image, ImageDraw, ImageFont
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN

OUTPUT_DIR = "/tmp/chart_images"
os.makedirs(OUTPUT_DIR, exist_ok=True)

def create_bar_chart(filename, title, data):
    img = Image.new('RGB', (800, 500), color='white')
    d = ImageDraw.Draw(img)
    # Draw axes
    d.line([(50, 50), (50, 450), (750, 450)], fill='black', width=2)
    # Draw title
    d.text((400, 20), title, fill='black', anchor="ms", font_size=20)
    
    bar_width = 600 // len(data)
    max_val = max(data.values())
    
    for i, (label, value) in enumerate(data.items()):
        x = 100 + i * bar_width
        height = (value / max_val) * 350
        y = 450 - height
        # Draw bar
        color = (46, 134, 171) # Blueish
        d.rectangle([x, y, x + bar_width - 20, 450], fill=color)
        # Draw label
        d.text((x + (bar_width-20)//2, 460), str(label), fill='black', anchor="mt")
        # Draw value
        d.text((x + (bar_width-20)//2, y - 15), str(value), fill='black', anchor="mb")
        
    img.save(os.path.join(OUTPUT_DIR, filename))

def create_pie_chart(filename, title, data):
    img = Image.new('RGB', (800, 500), color='white')
    d = ImageDraw.Draw(img)
    # Draw title
    d.text((400, 20), title, fill='black', anchor="ms", font_size=20)
    
    total = sum(data.values())
    start_angle = 0
    colors = [(46, 134, 171), (241, 143, 1), (162, 59, 114), (199, 62, 29)]
    
    # Bounding box for pie
    bbox = [250, 100, 550, 400]
    
    for i, (label, value) in enumerate(data.items()):
        extent = (value / total) * 360
        d.pieslice(bbox, start=start_angle, end=start_angle+extent, fill=colors[i % len(colors)])
        
        # Legend
        d.rectangle([600, 150 + i*30, 620, 170 + i*30], fill=colors[i % len(colors)])
        d.text((630, 150 + i*30), f"{label} ({int(value/total*100)}%)", fill='black')
        
        start_angle += extent
        
    img.save(os.path.join(OUTPUT_DIR, filename))

def create_line_chart(filename, title, data):
    img = Image.new('RGB', (800, 500), color='white')
    d = ImageDraw.Draw(img)
    d.line([(50, 50), (50, 450), (750, 450)], fill='black', width=2)
    d.text((400, 20), title, fill='black', anchor="ms", font_size=20)
    
    points = []
    years = list(data.keys())
    values = list(data.values())
    max_val = max(values)
    x_step = 650 // (len(years) - 1)
    
    for i, (year, value) in enumerate(data.items()):
        x = 75 + i * x_step
        y = 450 - (value / max_val * 350)
        points.append((x, y))
        d.text((x, 460), str(year), fill='black', anchor="mt")
        d.text((x, y - 20), str(value), fill='black', anchor="mb")
        d.ellipse([x-4, y-4, x+4, y+4], fill='blue')
        
    d.line(points, fill='blue', width=3)
    img.save(os.path.join(OUTPUT_DIR, filename))

def create_hbar_chart(filename, title, data):
    img = Image.new('RGB', (800, 500), color='white')
    d = ImageDraw.Draw(img)
    d.line([(150, 50), (150, 450), (750, 450)], fill='black', width=2)
    d.text((400, 20), title, fill='black', anchor="ms", font_size=20)
    
    bar_height = 350 // len(data)
    max_val = 5.0
    
    for i, (label, value) in enumerate(data.items()):
        y = 100 + i * bar_height
        width = (value / max_val) * 550
        
        d.rectangle([150, y, 150 + width, y + bar_height - 20], fill=(241, 143, 1))
        d.text((140, y + 20), label, fill='black', anchor="rm")
        d.text((150 + width + 10, y + 20), str(value), fill='black', anchor="lm")
        
    img.save(os.path.join(OUTPUT_DIR, filename))

# Generate images
create_bar_chart("chart1.png", "Volunteer Hours", {2019: 58000, 2020: 41000, 2021: 52000, 2022: 68000, 2023: 78000})
create_pie_chart("chart2.png", "Funding Sources", {"Gov Grants": 42, "Donations": 28, "Sponsors": 18, "Events": 12})
create_line_chart("chart3.png", "Beneficiaries", {2019: 1200, 2020: 1450, 2021: 1900, 2022: 2500, 2023: 3100})
create_hbar_chart("chart4.png", "Satisfaction", {"Mentoring": 4.7, "Food": 4.5, "Training": 4.3, "Housing": 4.1, "Health": 3.9})

# Create Presentation
prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

slides_info = [
    ("Volunteer Hours 2019-2023", "chart1.png"),
    ("Funding Sources Breakdown", "chart2.png"),
    ("Beneficiaries Served Over Time", "chart3.png"),
    ("Program Satisfaction Ratings", "chart4.png")
]

for title_text, img_name in slides_info:
    slide = prs.slides.add_slide(prs.slide_layouts[6]) # Blank
    
    # Title
    txBox = slide.shapes.add_textbox(Inches(0.5), Inches(0.3), Inches(12), Inches(1))
    p = txBox.text_frame.paragraphs[0]
    p.text = title_text
    p.font.size = Pt(32)
    p.font.bold = True
    p.alignment = PP_ALIGN.CENTER
    
    # Image
    img_path = os.path.join(OUTPUT_DIR, img_name)
    slide.shapes.add_picture(img_path, Inches(2.5), Inches(1.5), Inches(8.33), Inches(5))

prs.save("/home/ga/Documents/Presentations/community_impact_report.pptx")
PYEOF

# Run generation script
python3 /tmp/create_accessible_pres.py
chown ga:ga /home/ga/Documents/Presentations/community_impact_report.pptx

# Kill existing libreoffice
pkill -f soffice 2>/dev/null || true

# Launch Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/community_impact_report.pptx > /tmp/impress.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Impress" 60
wait_for_window "community_impact_report" 30

# Maximize
DISPLAY=:1 wmctrl -r "LibreOffice Impress" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_window "LibreOffice Impress"

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="