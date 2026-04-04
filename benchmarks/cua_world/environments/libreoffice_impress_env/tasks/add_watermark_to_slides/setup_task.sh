#!/bin/bash
set -euo pipefail

echo "=== Setting up Add Watermark Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create the initial presentation using Python and odfpy
# We use a python script to generate a realistic HR presentation
echo "Generating presentation file..."
python3 << 'PYEOF'
import sys
import os

# Ensure we can import odfpy
try:
    from odf.opendocument import OpenDocumentPresentation
    from odf import draw, text, style
    from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties, ParagraphProperties
    from odf.text import P, Span
except ImportError:
    print("Error: odfpy not installed")
    sys.exit(1)

output_path = "/home/ga/Documents/Presentations/benefits_overview.odp"

doc = OpenDocumentPresentation()

# --- Page Layout ---
pagelayout = PageLayout(name="MyLayout")
pagelayout.addElement(PageLayoutProperties(margin="0cm", pagewidth="25.4cm", pageheight="19.05cm", printorientation="landscape"))
doc.automaticstyles.addElement(pagelayout)

masterpage = MasterPage(name="Default", pagelayoutname=pagelayout)
doc.masterstyles.addElement(masterpage)

# --- Styles ---
# Title Style
title_style = Style(name="TitleStyle", family="presentation")
title_style.addElement(TextProperties(fontsize="32pt", fontweight="bold", fontfamily="Liberation Sans", color="#1a3c6e"))
title_style.addElement(GraphicProperties(fill="none", stroke="none"))
doc.automaticstyles.addElement(title_style)

# Body Style
body_style = Style(name="BodyStyle", family="presentation")
body_style.addElement(TextProperties(fontsize="20pt", fontfamily="Liberation Sans", color="#333333"))
body_style.addElement(GraphicProperties(fill="none", stroke="none"))
doc.automaticstyles.addElement(body_style)

# Text Styles
ts_title = Style(name="TitleText", family="text")
ts_title.addElement(TextProperties(fontsize="32pt", fontweight="bold", color="#1a3c6e"))
doc.automaticstyles.addElement(ts_title)

ts_bullet = Style(name="BulletText", family="text")
ts_bullet.addElement(TextProperties(fontsize="20pt", color="#333333"))
doc.automaticstyles.addElement(ts_bullet)

# Content Data
slides_data = [
    {
        "title": "2025 Employee Benefits Overview",
        "bullets": [
            "Annual enrollment period: March 1 - March 31",
            "Effective date for new benefits: May 1, 2025",
            "New: Expanded mental health coverage",
            "Contact HR for questions: benefits@company.com"
        ]
    },
    {
        "title": "Health Insurance Plans",
        "bullets": [
            "PPO Plan: $185/mo premium, $1500 deductible",
            "HMO Plan: $142/mo premium, $1000 deductible",
            "HDHP with HSA: $98/mo premium, employer HSA match",
            "All plans include free preventive care"
        ]
    },
    {
        "title": "Retirement and Savings Programs",
        "bullets": [
            "401(k) Match: 100% on first 4%, 50% on next 2%",
            "Vesting: Immediate eligibility, 3-year graded vesting",
            "Roth 401(k) option available",
            "Financial planning webinars quarterly"
        ]
    },
    {
        "title": "Paid Time Off and Leave Policies",
        "bullets": [
            "Base PTO: 15 days (0-3 years), 20 days (4-7 years)",
            "Holidays: 10 fixed + 2 floating per year",
            "Parental Leave: 12 weeks fully paid",
            "Sick Leave: 10 days per year"
        ]
    },
    {
        "title": "Wellness Programs and Perks",
        "bullets": [
            "Gym Reimbursement: Up to $75/month",
            "EAP: 8 free counseling sessions",
            "Hybrid Work: 3 days in office / 2 remote",
            "Tuition Assistance: $5250/year"
        ]
    }
]

# Create Slides
for slide_info in slides_data:
    page = draw.Page(masterpagename=masterpage)
    doc.presentation.addElement(page)
    
    # Title Box
    title_frame = draw.Frame(stylename=title_style, width="22cm", height="3cm", x="1.5cm", y="1cm")
    title_box = draw.TextBox()
    p = P(stylename=ts_title)
    p.addText(slide_info["title"])
    title_box.addElement(p)
    title_frame.addElement(title_box)
    page.addElement(title_frame)
    
    # Content Box
    content_frame = draw.Frame(stylename=body_style, width="22cm", height="12cm", x="1.5cm", y="5cm")
    content_box = draw.TextBox()
    for bullet in slide_info["bullets"]:
        p = P(stylename=ts_bullet)
        p.addText(u"• " + bullet)
        content_box.addElement(p)
    content_frame.addElement(content_box)
    page.addElement(content_frame)

doc.save(output_path)
print(f"Presentation saved to {output_path}")
PYEOF

# Set permissions
sudo chown ga:ga /home/ga/Documents/Presentations/benefits_overview.odp

# Record initial file state (size and mtime)
stat -c "%s %Y" /home/ga/Documents/Presentations/benefits_overview.odp > /tmp/initial_file_stat.txt

# Launch Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/benefits_overview.odp > /tmp/impress.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 90 "benefits_overview"

# Maximize window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Focusing and maximizing window $wid"
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any recovery/tip dialogs if they appear
    safe_xdotool ga :1 key Escape
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="