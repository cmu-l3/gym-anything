#!/bin/bash
set -e
echo "=== Setting up insert_images task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 1

# Create directories
PRES_DIR="/home/ga/Documents/Presentations"
IMG_DIR="$PRES_DIR/images"
mkdir -p "$PRES_DIR"
mkdir -p "$IMG_DIR"

# ============================================================
# Step 1: Generate chart images using Pillow
# ============================================================
echo "Generating chart images..."

python3 << 'PYEOF'
from PIL import Image, ImageDraw, ImageFont
import os

img_dir = "/home/ga/Documents/Presentations/images"

def create_chart(filename, title, data_type):
    width, height = 800, 500
    img = Image.new('RGB', (width, height), '#FFFFFF')
    draw = ImageDraw.Draw(img)
    
    # Try to load font, fallback to default
    try:
        font_title = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf", 24)
        font_text = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 16)
    except:
        font_title = ImageFont.load_default()
        font_text = ImageFont.load_default()

    # Draw Title
    draw.text((50, 20), title, fill='#333333', font=font_title)
    
    # Draw Axis
    draw.line([(50, 450), (750, 450)], fill='#000000', width=2) # X
    draw.line([(50, 450), (50, 100)], fill='#000000', width=2)  # Y

    if data_type == "bar":
        # Draw fake bars
        colors = ['#2196F3', '#4CAF50', '#FFC107', '#F44336']
        for i in range(4):
            h = [300, 250, 320, 280][i]
            x = 100 + i * 150
            draw.rectangle([x, 450-h, x+100, 450], fill=colors[i])
            draw.text((x+30, 460), f"Q{i+1}", fill='#000000', font=font_text)
            draw.text((x+30, 450-h-20), str(h), fill='#000000', font=font_text)
            
    elif data_type == "pie":
        # Draw fake pie
        bbox = [200, 100, 500, 400]
        draw.pieslice(bbox, 0, 90, fill='#2196F3')
        draw.pieslice(bbox, 90, 200, fill='#4CAF50')
        draw.pieslice(bbox, 200, 360, fill='#FFC107')
        # Legend
        draw.rectangle([550, 150, 570, 170], fill='#2196F3')
        draw.text((580, 150), "Category A", fill='#000000', font=font_text)
        draw.rectangle([550, 200, 570, 220], fill='#4CAF50')
        draw.text((580, 200), "Category B", fill='#000000', font=font_text)
        draw.rectangle([550, 250, 570, 270], fill='#FFC107')
        draw.text((580, 250), "Category C", fill='#000000', font=font_text)

    img.save(os.path.join(img_dir, filename))
    print(f"Created {filename}")

create_chart("energy_chart.png", "Quarterly Energy Consumption (MWh)", "bar")
create_chart("waste_breakdown.png", "Waste Stream Breakdown", "pie")
create_chart("water_usage.png", "Monthly Water Usage (kL)", "bar")
PYEOF

# ============================================================
# Step 2: Create the base presentation using python-pptx
# ============================================================
echo "Creating base presentation..."

python3 << 'PYEOF'
from pptx import Presentation
from pptx.util import Inches

prs = Presentation()
# Title Slide
slide = prs.slides.add_slide(prs.slide_layouts[0])
slide.shapes.title.text = "Q3 2024 Sustainability Report"
slide.placeholders[1].text = "GreenTech Solutions Inc."

# Slide 2: Energy
slide = prs.slides.add_slide(prs.slide_layouts[1])
slide.shapes.title.text = "Energy Consumption Overview"
tf = slide.placeholders[1].text_frame
tf.text = "Total energy consumed: 3,420 MWh"
p = tf.add_paragraph()
p.text = "Reduced by 17% Year-over-Year"

# Slide 3: Waste
slide = prs.slides.add_slide(prs.slide_layouts[1])
slide.shapes.title.text = "Waste Reduction Progress"
tf = slide.placeholders[1].text_frame
tf.text = "Diversion rate reached 88.4%"
p = tf.add_paragraph()
p.text = "Composting program expanded"

# Slide 4: Water
slide = prs.slides.add_slide(prs.slide_layouts[1])
slide.shapes.title.text = "Water Conservation Results"
tf = slide.placeholders[1].text_frame
tf.text = "Water usage down by 12%"
p = tf.add_paragraph()
p.text = "New recycling system operational"

# Slide 5: Targets
slide = prs.slides.add_slide(prs.slide_layouts[1])
slide.shapes.title.text = "Next Quarter Targets"
tf = slide.placeholders[1].text_frame
tf.text = "Goal: 90% waste diversion"
p = tf.add_paragraph()
p.text = "Goal: Carbon neutral by 2030"

pptx_path = "/home/ga/Documents/Presentations/sustainability_report.pptx"
prs.save(pptx_path)
PYEOF

# Convert PPTX to ODP using headless LibreOffice
echo "Converting to ODP format..."
cd "$PRES_DIR"
libreoffice --headless --convert-to odp sustainability_report.pptx --outdir "$PRES_DIR" 2>/dev/null
rm -f sustainability_report.pptx

# Set ownership
chown -R ga:ga "$PRES_DIR"

# ============================================================
# Step 3: Launch Impress
# ============================================================
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$PRES_DIR/sustainability_report.odp' > /tmp/impress.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Impress" 30

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Dismiss any potential recovery dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="