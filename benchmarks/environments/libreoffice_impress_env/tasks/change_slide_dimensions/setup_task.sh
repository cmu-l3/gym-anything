#!/bin/bash
set -e
echo "=== Setting up change_slide_dimensions task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Create directories
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create the initial 4:3 presentation using Python/odfpy
cat > /tmp/create_presentation.py << 'PYEOF'
#!/usr/bin/env python3
"""Create a 4-slide IT strategy presentation in 4:3 format using odfpy"""
import sys
try:
    from odf.opendocument import OpenDocumentPresentation
    from odf import draw, text, style, presentation
    from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, GraphicProperties, TextProperties, ParagraphProperties
    from odf.text import P, Span
except ImportError:
    print("odfpy not installed")
    sys.exit(1)

output_path = "/home/ga/Documents/Presentations/it_strategy_q4.odp"

doc = OpenDocumentPresentation()

# --- Page Layout (4:3 standard) ---
pagelayout = PageLayout(name="PM0")
plp = PageLayoutProperties(
    margintop="0cm",
    marginbottom="0cm",
    marginleft="0cm",
    marginright="0cm",
    pagewidth="25.4cm",
    pageheight="19.05cm",
    printorientation="landscape"
)
pagelayout.addElement(plp)
doc.automaticstyles.addElement(pagelayout)

# --- Styles for title text ---
title_style = Style(name="TitleStyle", family="presentation")
title_style.addElement(TextProperties(
    fontsize="32pt",
    fontweight="bold",
    color="#1a3c6e"
))
doc.automaticstyles.addElement(title_style)

# --- Style for body text ---
body_style = Style(name="BodyStyle", family="presentation")
body_style.addElement(TextProperties(
    fontsize="18pt",
    color="#333333"
))
doc.automaticstyles.addElement(body_style)

# --- Drawing page style ---
dp_style = Style(name="dp1", family="drawing-page")
dp_style.addElement(style.DrawingPageProperties(
    fill="solid",
    fillcolor="#ffffff"
))
doc.automaticstyles.addElement(dp_style)

# --- Master page ---
masterpage = MasterPage(name="Default", pagelayoutname=pagelayout)
doc.masterstyles.addElement(masterpage)

# --- Slide content definitions ---
slides_content = [
    {
        "title": "Q4 IT Strategy Update",
        "bullets": [
            "Enterprise Architecture Roadmap 2024-2025",
            "Key initiatives across infrastructure, security, and digital transformation",
            "Prepared for Executive Leadership Team"
        ]
    },
    {
        "title": "Infrastructure Modernization",
        "bullets": [
            "Cloud migration: 60% of workloads targeted for AWS/Azure by Q2 2025",
            "Legacy server decommission: 140 physical servers to be retired",
            "Network refresh: SD-WAN deployment across 12 regional offices",
            "Estimated annual savings: $2.3M in operational costs"
        ]
    },
    {
        "title": "Cybersecurity Initiatives",
        "bullets": [
            "Zero Trust architecture rollout beginning January 2025",
            "Mandatory security awareness training for all 3,200 employees",
            "SOC upgrade: 24/7 monitoring with SIEM integration",
            "Incident response time target: under 15 minutes for critical alerts"
        ]
    },
    {
        "title": "Budget and Timeline",
        "bullets": [
            "Total IT budget allocation: $18.7M for FY2025",
            "Infrastructure: $7.2M | Security: $4.1M | Digital: $5.8M | Reserve: $1.6M",
            "Phase 1 (Q1): Planning and vendor selection complete",
            "Phase 2 (Q2-Q3): Implementation and migration execution",
            "Phase 3 (Q4): Optimization, testing, and handoff to operations"
        ]
    }
]

# --- Create slides ---
for slide_data in slides_content:
    page = draw.Page(stylename=dp_style, masterpagename=masterpage)

    # Title text frame
    title_frame = draw.Frame(stylename=title_style, width="23cm", height="3cm", x="1.2cm", y="0.8cm")
    title_box = draw.TextBox()
    title_p = P()
    title_p.addText(slide_data["title"])
    title_box.addElement(title_p)
    title_frame.addElement(title_box)
    page.addElement(title_frame)

    # Bullet points text frame
    body_frame = draw.Frame(stylename=body_style, width="23cm", height="13cm", x="1.2cm", y="4.5cm")
    body_box = draw.TextBox()
    for bullet in slide_data["bullets"]:
        bullet_p = P()
        bullet_p.addText("• " + bullet)
        body_box.addElement(bullet_p)
    body_frame.addElement(body_box)
    page.addElement(body_frame)

    doc.presentation.addElement(page)

doc.save(output_path)
print(f"Created presentation at {output_path}")
PYEOF

# Execute the python script
python3 /tmp/create_presentation.py

# Verify the file was created
if [ ! -f "/home/ga/Documents/Presentations/it_strategy_q4.odp" ]; then
    echo "ERROR: Presentation file was not created!"
    exit 1
fi

# Set ownership
chown ga:ga /home/ga/Documents/Presentations/it_strategy_q4.odp

# Launch LibreOffice Impress with the file
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/it_strategy_q4.odp > /tmp/impress.log 2>&1 &"

# Wait for Impress window
echo "Waiting for Impress window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "impress\|it_strategy"; then
        echo "Impress window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 3

# Maximize the window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "LibreOffice Impress" 2>/dev/null || true

# Dismiss any startup dialogs (Esc key)
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Presentation loaded: /home/ga/Documents/Presentations/it_strategy_q4.odp"
echo "Format: 4:3 standard"