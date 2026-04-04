#!/bin/bash
set -euo pipefail

echo "=== Setting up rotate_shapes_precise task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Ensure target directory exists
mkdir -p /home/ga/Documents/Presentations
chown ga:ga /home/ga/Documents/Presentations

# Create the initial presentation with shapes using Python and odfpy
# We use Python here because creating specific ODP shapes with names via CLI is impossible
echo "Generating initial presentation..."
cat > /tmp/create_presentation.py << 'PYEOF'
#!/usr/bin/env python3
import sys
import os
from odf.opendocument import OpenDocumentPresentation
from odf import draw, style, text
from odf.style import Style, GraphicProperties, ParagraphProperties, TextProperties, DrawingPageProperties, PageLayout, PageLayoutProperties
from odf.text import P

output_path = "/home/ga/Documents/Presentations/design_review.odp"

doc = OpenDocumentPresentation()

# --- Styles ---
# Page Layout
pagelayout = PageLayout(name="MyLayout")
doc.automaticstyles.addElement(pagelayout)
plp = PageLayoutProperties(margin="0cm", pagewidth="28cm", pageheight="21cm", printorientation="landscape")
pagelayout.addElement(plp)

# Master Page
masterpage = style.MasterPage(name="Default", pagelayoutname=pagelayout)
doc.masterstyles.addElement(masterpage)

# Controller Style (Blue Rect)
s_rect = Style(name="ControllerStyle", family="graphic")
s_rect.addElement(GraphicProperties(fill="solid", fillcolor="#4472c4", stroke="solid", strokecolor="#1a3c6e", strokewidth="0.05cm"))
s_rect.addElement(ParagraphProperties(textalign="center"))
s_rect.addElement(TextProperties(fontsize="12pt", color="#ffffff", fontweight="bold"))
doc.automaticstyles.addElement(s_rect)

# DataFlow Style (Green Arrow)
s_arrow = Style(name="DataFlowStyle", family="graphic")
s_arrow.addElement(GraphicProperties(fill="solid", fillcolor="#70ad47", stroke="solid", strokecolor="#2e7d32", strokewidth="0.05cm"))
s_arrow.addElement(ParagraphProperties(textalign="center"))
s_arrow.addElement(TextProperties(fontsize="10pt", color="#ffffff", fontweight="bold"))
doc.automaticstyles.addElement(s_arrow)

# IOPort Style (Red Diamond)
s_diamond = Style(name="IOPortStyle", family="graphic")
s_diamond.addElement(GraphicProperties(fill="solid", fillcolor="#c0392b", stroke="solid", strokecolor="#8b0000", strokewidth="0.05cm"))
s_diamond.addElement(ParagraphProperties(textalign="center"))
s_diamond.addElement(TextProperties(fontsize="10pt", color="#ffffff", fontweight="bold"))
doc.automaticstyles.addElement(s_diamond)

# Instruction Text Style
s_instr = Style(name="InstrStyle", family="graphic")
s_instr.addElement(GraphicProperties(fill="none", stroke="none"))
s_instr.addElement(ParagraphProperties(textalign="center"))
s_instr.addElement(TextProperties(fontsize="10pt", color="#555555"))
doc.automaticstyles.addElement(s_instr)

# --- Slide Content ---
page = draw.Page(name="ComponentLayout", masterpagename=masterpage)
doc.presentation.addElement(page)

# Title
title_frame = draw.Frame(name="Title", width="25cm", height="2cm", x="1.5cm", y="1cm", stylename=s_instr)
tb = draw.TextBox()
title_frame.addElement(tb)
tb.addElement(P(text="Component Layout - Design Review"))
page.addElement(title_frame)

# 1. Controller (Rectangle)
# Expected: Rotate to 90
rect = draw.Rect(name="Controller", stylename=s_rect, width="5cm", height="3cm", x="3cm", y="6cm")
rect_tb = draw.TextBox()
rect.addElement(rect_tb)
rect_tb.addElement(P(text="Controller"))
page.addElement(rect)

# Label 1
l1 = draw.Frame(width="5cm", height="1cm", x="3cm", y="9.2cm", stylename=s_instr)
l1_tb = draw.TextBox()
l1.addElement(l1_tb)
l1_tb.addElement(P(text="Target: 90°"))
page.addElement(l1)

# 2. DataFlow (CustomShape Arrow)
# Expected: Rotate to 45
arrow = draw.CustomShape(name="DataFlow", stylename=s_arrow, width="4cm", height="2cm", x="11cm", y="6.5cm")
geom_arrow = draw.EnhancedGeometry(type="right-arrow", viewbox="0 0 21600 21600")
arrow.addElement(geom_arrow)
arrow_tb = draw.TextBox()
arrow.addElement(arrow_tb)
arrow_tb.addElement(P(text="DataFlow"))
page.addElement(arrow)

# Label 2
l2 = draw.Frame(width="4cm", height="1cm", x="11cm", y="9.2cm", stylename=s_instr)
l2_tb = draw.TextBox()
l2.addElement(l2_tb)
l2_tb.addElement(P(text="Target: 45°"))
page.addElement(l2)

# 3. IOPort (CustomShape Diamond)
# Expected: Rotate to 180
diamond = draw.CustomShape(name="IOPort", stylename=s_diamond, width="3.5cm", height="3.5cm", x="19cm", y="5.75cm")
geom_diamond = draw.EnhancedGeometry(type="diamond", viewbox="0 0 21600 21600")
diamond.addElement(geom_diamond)
diamond_tb = draw.TextBox()
diamond.addElement(diamond_tb)
diamond_tb.addElement(P(text="IOPort"))
page.addElement(diamond)

# Label 3
l3 = draw.Frame(width="3.5cm", height="1cm", x="19cm", y="9.5cm", stylename=s_instr)
l3_tb = draw.TextBox()
l3.addElement(l3_tb)
l3_tb.addElement(P(text="Target: 180°"))
page.addElement(l3)

doc.save(output_path)
print(f"Created {output_path}")
PYEOF

python3 /tmp/create_presentation.py
chown ga:ga /home/ga/Documents/Presentations/design_review.odp

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/design_review.odp > /tmp/impress.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Impress" 60
wait_for_window "design_review" 30 || true

# Maximize and focus
WID=$(get_impress_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (like Tip of the Day)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="