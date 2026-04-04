#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Slide Layering Visibility Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directory exists
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create the initial "broken" presentation programmatically using odfpy
# We need to explicitly create objects in the WRONG order to simulate the layering issue
# In ODF, later elements are drawn ON TOP of earlier elements.

echo "Generating presentation file..."
cat > /tmp/gen_presentation.py << 'PYEOF'
import sys
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties, ParagraphProperties, DrawingPageProperties
from odf.draw import Page, Frame, TextBox, Image as DrawImage, Rect, CustomShape, EnhancedGeometry
from odf.text import P, Span

def create_broken_presentation():
    doc = OpenDocumentPresentation()

    # Create styles
    # Style for text labels
    label_style = Style(name="LabelStyle", family="graphic")
    label_style.addElement(GraphicProperties(fill="none", stroke="none"))
    label_style.addElement(TextProperties(fontsize="24pt", fontweight="bold", color="#000000"))
    doc.styles.addElement(label_style)
    
    # Style for yellow highlight box
    box_style = Style(name="BoxStyle", family="graphic")
    box_style.addElement(GraphicProperties(fillcolor="#ffff00", fill="solid", stroke="none", transparency="50%"))
    doc.styles.addElement(box_style)

    # Style for map image (placeholder style)
    img_style = Style(name="ImgStyle", family="graphic")
    img_style.addElement(GraphicProperties(fill="none", stroke="none"))
    doc.styles.addElement(img_style)
    
    # Style for DRAFT watermark
    draft_style = Style(name="DraftStyle", family="graphic")
    draft_style.addElement(GraphicProperties(fillcolor="#ff0000", fill="solid", stroke="none", transparency="30%"))
    doc.styles.addElement(draft_style)
    
    # Style for DRAFT text
    draft_text_style = Style(name="DraftTextStyle", family="paragraph")
    draft_text_style.addElement(TextProperties(fontsize="48pt", fontweight="bold", color="#ffffff"))
    doc.styles.addElement(draft_text_style)

    # --- SLIDE 1: Regional Sales ---
    # Issue: Map is on top of Text
    page1 = Page(name="Regional Sales")
    doc.presentation.addElement(page1)
    
    # 1. Add Title
    title_frame = Frame(width="25cm", height="3cm", x="1cm", y="1cm")
    title_box = TextBox()
    title_box.addElement(P(text="Regional Sales Overview"))
    title_frame.addElement(title_box)
    page1.addElement(title_frame)

    # 2. Add Text Labels (These should be on top, but we add them early so they are at bottom of stack)
    # Label 1: West Region
    text_frame_w = Frame(width="6cm", height="2cm", x="3cm", y="8cm", stylename=label_style)
    tb_w = TextBox()
    tb_w.addElement(P(text="West Region"))
    text_frame_w.addElement(tb_w)
    page1.addElement(text_frame_w)
    
    # Label 2: East Region
    text_frame_e = Frame(width="6cm", height="2cm", x="15cm", y="8cm", stylename=label_style)
    tb_e = TextBox()
    tb_e.addElement(P(text="East Region"))
    text_frame_e.addElement(tb_e)
    page1.addElement(text_frame_e)
    
    # 3. Add Yellow Highlight Box (Middle layer)
    # Covering West Region text roughly
    rect = Rect(width="7cm", height="3cm", x="2.5cm", y="7.5cm", stylename=box_style)
    page1.addElement(rect)

    # 4. Add Map Image (Top layer - obscuring everything)
    # We'll use a colored rectangle to simulate a map if we don't have an image file,
    # but let's try to generate a placeholder image file or just use a big rectangle named "Map"
    # Using a Frame with a name "MapImage" and a background color is safer than depending on external assets
    map_frame = Frame(name="MapImage", width="24cm", height="12cm", x="2cm", y="5cm")
    # Styling it to look like a map (blue background)
    map_style = Style(name="MapPlaceHolder", family="graphic")
    map_style.addElement(GraphicProperties(fillcolor="#aaccff", fill="solid"))
    doc.styles.addElement(map_style)
    map_frame.setAttribute("stylename", map_style)
    
    # Add a text inside saying "MAP DATA"
    map_tb = TextBox()
    map_tb.addElement(P(text="[MAP IMAGE PLACEHOLDER]"))
    map_frame.addElement(map_tb)
    
    page1.addElement(map_frame)


    # --- SLIDE 2: Q4 Projections ---
    # Issue: Watermark is on top of Text
    page2 = Page(name="Q4 Projections")
    doc.presentation.addElement(page2)
    
    # 1. Add Title
    title_frame2 = Frame(width="25cm", height="3cm", x="1cm", y="1cm")
    title_box2 = TextBox()
    title_box2.addElement(P(text="Q4 Projections"))
    title_frame2.addElement(title_box2)
    page2.addElement(title_frame2)
    
    # 2. Add Content Text (Bullet points)
    content_frame = Frame(name="ContentText", width="20cm", height="10cm", x="2cm", y="5cm")
    content_box = TextBox()
    content_box.addElement(P(text="• Revenue forecast: $1.2M"))
    content_box.addElement(P(text="• Growth target: 15%"))
    content_box.addElement(P(text="• New hires: 5"))
    content_frame.addElement(content_box)
    page2.addElement(content_frame)
    
    # 3. Add "DRAFT" Watermark (Top layer - obscuring text)
    # Using a CustomShape or just a rotated text frame
    draft_frame = Frame(name="DraftWatermark", width="15cm", height="5cm", x="5cm", y="8cm", stylename=draft_style)
    # Rotate it
    draft_frame.setAttribute("transform", "rotate(-30) translate(10cm 10cm)")
    
    draft_box = TextBox()
    p_draft = P(text="DRAFT", stylename=draft_text_style)
    draft_box.addElement(p_draft)
    draft_frame.addElement(draft_box)
    
    page2.addElement(draft_frame)

    doc.save("/home/ga/Documents/Presentations/territory_analysis.odp")

create_broken_presentation()
PYEOF

# Execute generation script
python3 /tmp/gen_presentation.py
sudo chown ga:ga /home/ga/Documents/Presentations/territory_analysis.odp

# Start LibreOffice Impress
echo "Starting LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/territory_analysis.odp > /tmp/impress_launch.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 20
if wait_for_window "LibreOffice Impress" 60; then
    echo "Window detected."
else
    echo "WARNING: Window detection timed out, continuing anyway..."
fi

# Get window ID and maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Maximizing window $wid..."
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Ensure Slide 1 is selected
    safe_xdotool ga :1 key Home
else
    echo "WARNING: Could not find Impress window ID."
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="