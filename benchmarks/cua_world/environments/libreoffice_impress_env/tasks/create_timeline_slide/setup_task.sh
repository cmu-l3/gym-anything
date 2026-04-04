#!/bin/bash
set -e
echo "=== Setting up Create Cloud Migration Timeline Slide task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Create working directory
mkdir -p /home/ga/Documents/Presentations
chown -R ga:ga /home/ga/Documents

# Generate the initial 3-slide presentation using Python + odfpy
# We generate this inside the container to ensure compatibility
cat > /tmp/create_initial_presentation.py << 'PYEOF'
#!/usr/bin/env python3
from odf.opendocument import OpenDocumentPresentation
from odf import draw, text, style
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties

output_path = "/home/ga/Documents/Presentations/it_strategy.odp"

doc = OpenDocumentPresentation()

# Define page layout
pagelayout = PageLayout(name="MyLayout")
pagelayout.addElement(PageLayoutProperties(margin="0cm", pagewidth="25.4cm", pageheight="19.05cm", printorientation="landscape"))
doc.automaticstyles.addElement(pagelayout)

# Define master page
masterpage = MasterPage(name="Default", pagelayoutname=pagelayout)
doc.masterstyles.addElement(masterpage)

# Styles
titlestyle = Style(name="TitleStyle", family="presentation")
titlestyle.addElement(TextProperties(fontsize="32pt", fontweight="bold", color="#333333", fontfamily="Liberation Sans"))
doc.automaticstyles.addElement(titlestyle)

bodystyle = Style(name="BodyStyle", family="presentation")
bodystyle.addElement(TextProperties(fontsize="20pt", color="#555555", fontfamily="Liberation Sans"))
doc.automaticstyles.addElement(bodystyle)

def add_slide(doc, title_text, body_lines):
    page = draw.Page(stylename=masterpage, name=f"Slide{len(doc.getElementsByType(draw.Page))+1}", masterpagename=masterpage)
    
    # Title Frame
    titleframe = draw.Frame(width="22cm", height="3cm", x="1.5cm", y="1cm")
    titlebox = draw.TextBox()
    titlebox.addElement(text.P(stylename=titlestyle, text=title_text))
    titleframe.addElement(titlebox)
    page.addElement(titleframe)
    
    # Body Frame
    bodyframe = draw.Frame(width="22cm", height="12cm", x="1.5cm", y="5cm")
    bodybox = draw.TextBox()
    for line in body_lines:
        bodybox.addElement(text.P(stylename=bodystyle, text=line))
    bodyframe.addElement(bodybox)
    page.addElement(bodyframe)
    
    doc.presentation.addElement(page)

# Slide 1
add_slide(doc, "IT Infrastructure Modernization Plan", [
    "Enterprise Technology Division",
    "Fiscal Year 2025-2026 Strategic Initiative",
    "Prepared for Executive Leadership Review"
])

# Slide 2
add_slide(doc, "Current State Assessment", [
    "On-premises data center at 87% capacity",
    "Legacy applications averaging 8+ years old",
    "Maintenance costs rising 15% YoY"
])

# Slide 3
add_slide(doc, "Strategic Objectives", [
    "Migrate 80% of workloads to cloud by Q1 2026",
    "Reduce infrastructure costs by 35%",
    "Implement zero-trust security architecture"
])

doc.save(output_path)
PYEOF

# Run generation script
python3 /tmp/create_initial_presentation.py

# Save initial state statistics for anti-gaming
if [ -f "/home/ga/Documents/Presentations/it_strategy.odp" ]; then
    chown ga:ga /home/ga/Documents/Presentations/it_strategy.odp
    stat -c %s /home/ga/Documents/Presentations/it_strategy.odp > /tmp/initial_file_size.txt
    cp /home/ga/Documents/Presentations/it_strategy.odp /tmp/it_strategy_initial.odp
else
    echo "ERROR: Failed to create initial presentation"
    exit 1
fi

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/it_strategy.odp > /tmp/impress.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Impress" 60

# Maximize window
DISPLAY=:1 wmctrl -r "LibreOffice Impress" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Dismiss any startup dialogs (like 'Recovery', 'Tips')
sleep 2
safe_xdotool ga :1 key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="