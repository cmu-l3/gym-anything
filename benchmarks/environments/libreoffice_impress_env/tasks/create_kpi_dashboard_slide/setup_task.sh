#!/bin/bash
set -euo pipefail

echo "=== Setting up KPI Dashboard Slide task ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/Presentations
mkdir -p /home/ga/Documents/results
chown -R ga:ga /home/ga/Documents

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Create the initial 4-slide presentation using Python + odfpy
# We use the environment's python which has odfpy installed
echo "Generating initial presentation..."
python3 << 'PYEOF'
import sys
import os
# Ensure utils are importable if needed, though we use direct odfpy here
sys.path.append('/workspace/utils')

from odf.opendocument import OpenDocumentPresentation
from odf import draw, text, presentation, style
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties
from odf.style import TextProperties, ParagraphProperties, GraphicProperties
from odf.text import P

doc = OpenDocumentPresentation()

# Basic Styles
titlestyle = Style(name="MyTitle", family="presentation")
titlestyle.addElement(TextProperties(fontsize="36pt", fontweight="bold", fontfamily="Liberation Sans"))
doc.automaticstyles.addElement(titlestyle)

bodystyle = Style(name="MyBody", family="presentation")
bodystyle.addElement(TextProperties(fontsize="24pt", fontfamily="Liberation Sans"))
doc.automaticstyles.addElement(bodystyle)

def add_slide(doc, title_text, bullet_items):
    page = draw.Page(name=title_text[:10])
    doc.presentation.addElement(page)
    
    # Title Frame
    title_frame = draw.Frame(stylename=titlestyle, width="25cm", height="3cm", x="1.5cm", y="1cm")
    page.addElement(title_frame)
    textbox = draw.TextBox()
    title_frame.addElement(textbox)
    textbox.addElement(P(text=title_text))
    
    # Content Frame
    content_frame = draw.Frame(stylename=bodystyle, width="25cm", height="12cm", x="1.5cm", y="5cm")
    page.addElement(content_frame)
    textbox = draw.TextBox()
    content_frame.addElement(textbox)
    for item in bullet_items:
        textbox.addElement(P(text="• " + item))

# Slide 1
add_slide(doc, "Quarterly Sustainability Report - Q3 2024", [
    "Environmental Performance Division",
    "Confidential - Internal Use Only",
    "Date: October 15, 2024"
])

# Slide 2
add_slide(doc, "Environmental Goals", [
    "Reduce Scope 1 and 2 emissions by 15% year-over-year",
    "Achieve 80% waste diversion from landfill by end of fiscal year",
    "Decrease water consumption intensity by 10% across all facilities",
    "Transition 30% of energy portfolio to renewable sources"
])

# Slide 3
add_slide(doc, "Progress Summary", [
    "Emissions reduction program on track with 8% decrease achieved",
    "New waste sorting infrastructure deployed at 12 of 15 sites",
    "Water recycling systems operational at primary manufacturing facility",
    "Solar PPA signed covering 22% of total energy consumption"
])

# Slide 4
add_slide(doc, "Next Steps", [
    "Complete Scope 3 emissions inventory by end of Q4",
    "Launch employee engagement sustainability challenge in October",
    "Submit CDP Climate Change questionnaire by November deadline",
    "Begin feasibility study for on-site water treatment at Site B"
])

output_path = "/home/ga/Documents/Presentations/sustainability_report.odp"
doc.save(output_path)
print(f"Saved to {output_path}")
PYEOF

# Ensure ownership
chown ga:ga /home/ga/Documents/Presentations/sustainability_report.odp

# Record initial slide count (should be 4)
echo "4" > /tmp/initial_slide_count.txt

# Launch LibreOffice Impress
echo "Launching LibreOffice..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/sustainability_report.odp > /tmp/impress.log 2>&1 &"

# Wait for window
echo "Waiting for Impress window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "impress"; then
        echo "Window found"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "LibreOffice Impress" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "LibreOffice Impress" 2>/dev/null || true

# Dismiss common startup dialogs if they appear (Tips, etc.)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="