#!/bin/bash
set -e
echo "=== Setting up Add Speaker Notes task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Create presentation directory
PRES_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$PRES_DIR"
TARGET_FILE="$PRES_DIR/community_impact_report.odp"

# Generate the initial presentation using odfpy
# We use a python script to ensure a clean, valid ODP structure
cat > /tmp/create_presentation.py << 'PYEOF'
#!/usr/bin/env python3
import sys
from odf.opendocument import OpenDocumentPresentation
from odf import draw, text, style
from odf.text import P, Span
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties
from odf.style import GraphicProperties, ParagraphProperties, TextProperties, DrawingPageProperties

output_path = sys.argv[1]
doc = OpenDocumentPresentation()

# Styles
pagelayout = PageLayout(name="MyLayout")
pagelayout.addElement(PageLayoutProperties(margin="0cm", pagewidth="28cm", pageheight="15.75cm", printorientation="landscape"))
doc.automaticstyles.addElement(pagelayout)

masterpage = MasterPage(name="Default", pagelayoutname=pagelayout)
doc.masterstyles.addElement(masterpage)

dpstyle = Style(name="dp1", family="drawing-page")
dpstyle.addElement(DrawingPageProperties(fill="none"))
doc.automaticstyles.addElement(dpstyle)

titlestyle = Style(name="title", family="presentation")
titlestyle.addElement(ParagraphProperties(textalign="center"))
titlestyle.addElement(TextProperties(fontsize="36pt", fontweight="bold"))
doc.automaticstyles.addElement(titlestyle)

bodystyle = Style(name="body", family="presentation")
bodystyle.addElement(ParagraphProperties(textalign="start"))
bodystyle.addElement(TextProperties(fontsize="18pt"))
doc.automaticstyles.addElement(bodystyle)

# Slides Content
slides = [
    ("Annual Community Impact Report 2024", ["Building Stronger Communities Together", "Presented by: Social Services Dept"]),
    ("Program Overview", ["Youth Mentorship Program: 450 youth matched", "Family Support Services: 820 families assisted", "Senior Companion Program: 390 seniors served", "Community Food Pantry: 860 households supported"]),
    ("Volunteer Engagement", ["1,850 registered active volunteers", "47,000 total volunteer hours", "15% year-over-year increase", "98 corporate partners"]),
    ("Financial Summary", ["Total operating budget: $2.8 million", "Federal/State grants: 45%", "Individual donations: 30%", "Administrative overhead: 11%"]),
    ("Community Outcomes", ["Housing stability improved 23%", "Employment rates increased 18%", "Food insecurity decreased 31%", "School attendance improved 27%"]),
    ("Goals for 2025", ["Expand Youth Mentorship to two counties", "Launch Workforce Development Initiative", "Increase volunteer base by 20%", "Establish mobile food pantry"])
]

for title, points in slides:
    page = draw.Page(stylename=dpstyle, masterpagename=masterpage)
    
    # Title Frame
    t_frame = draw.Frame(stylename=titlestyle, width="24cm", height="3cm", x="2cm", y="1cm")
    t_box = draw.TextBox()
    t_box.addElement(P(text=title))
    t_frame.addElement(t_box)
    page.addElement(t_frame)
    
    # Body Frame
    b_frame = draw.Frame(stylename=bodystyle, width="24cm", height="10cm", x="2cm", y="5cm")
    b_box = draw.TextBox()
    for point in points:
        b_box.addElement(P(text=f"• {point}"))
    b_frame.addElement(b_box)
    page.addElement(b_frame)
    
    doc.presentation.addElement(page)

doc.save(output_path)
print(f"Created {output_path}")
PYEOF

# Run the generation script
sudo -u ga python3 /tmp/create_presentation.py "$TARGET_FILE"

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$TARGET_FILE' > /tmp/impress.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Impress" 30

# Maximize and focus
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (like "Tip of the Day")
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="