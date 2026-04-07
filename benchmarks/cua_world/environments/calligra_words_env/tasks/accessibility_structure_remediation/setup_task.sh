#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Accessibility Structure Remediation Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

install -d -o ga -g ga /home/ga/Documents
kill_calligra_processes
rm -f /home/ga/Documents/draft_equity_plan.odt
rm -f /home/ga/Documents/accessible_equity_plan.odt

# Create the improperly formatted document
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import P, Tab

doc = OpenDocumentText()

# Define fake visual styles (making them look like headings but functionally just paragraphs)
title_style = Style(name="FakeTitle", family="paragraph")
title_style.addElement(TextProperties(fontsize="24pt", fontweight="bold"))
title_style.addElement(ParagraphProperties(textalign="center", marginbottom="0.5cm"))
doc.automaticstyles.addElement(title_style)

h1_style = Style(name="FakeH1", family="paragraph")
h1_style.addElement(TextProperties(fontsize="18pt", fontweight="bold"))
h1_style.addElement(ParagraphProperties(margintop="0.4cm", marginbottom="0.2cm"))
doc.automaticstyles.addElement(h1_style)

h2_style = Style(name="FakeH2", family="paragraph")
h2_style.addElement(TextProperties(fontsize="14pt", fontweight="bold"))
h2_style.addElement(ParagraphProperties(margintop="0.3cm", marginbottom="0.1cm"))
doc.automaticstyles.addElement(h2_style)

body_style = Style(name="Body", family="paragraph")
body_style.addElement(TextProperties(fontsize="12pt"))
body_style.addElement(ParagraphProperties(marginbottom="0.2cm"))
doc.automaticstyles.addElement(body_style)

def add_para(text, style):
    p = P(stylename=style)
    parts = text.split('\t')
    for i, part in enumerate(parts):
        if i > 0:
            p.addElement(Tab())
        p.addText(part)
    doc.text.addElement(p)

# Document Content
add_para("State Broadband Development Office - Digital Equity Plan", title_style)

add_para("Executive Summary", h1_style)
add_para("The State Broadband Development Office presents this Digital Equity Plan to outline our strategy for ensuring all residents have access to affordable, reliable high-speed internet. This document serves as a blueprint for the next five years of infrastructure development.", body_style)

add_para("Current Landscape", h1_style)
add_para("According to recent state-wide surveys, significant gaps remain in broadband coverage, particularly in rural and economically disadvantaged urban areas. These gaps affect education, healthcare access, and economic opportunity.", body_style)

add_para("Infrastructure Gap", h2_style)
add_para("Approximately 15% of the state lacks high-speed broadband infrastructure capable of delivering 100 Mbps download speeds. The cost of last-mile deployment remains the primary barrier.", body_style)

add_para("Digital Literacy", h2_style)
add_para("Access alone is insufficient for digital equity. Nearly 22% of adults in targeted regions report lacking the basic digital skills required for modern workforce participation and telehealth services.", body_style)

add_para("Strategic Goals", h1_style)
add_para("- Expand fiber network to 90% of rural areas within 3 years.", body_style)
add_para("- Provide low-cost device options to 50,000 low-income households.", body_style)
add_para("- Partner with local libraries for community digital literacy training.", body_style)

add_para("Regional Funding Allocation", h1_style)
add_para("Region\tUnserved Households\tAllocation", body_style)
add_para("North\t12,500\t$45M", body_style)
add_para("South\t18,200\t$68M", body_style)
add_para("East\t8,400\t$22M", body_style)
add_para("West\t14,100\t$50M", body_style)

doc.save("/home/ga/Documents/draft_equity_plan.odt")
PYEOF

chown ga:ga /home/ga/Documents/draft_equity_plan.odt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/draft_equity_plan.odt"
sleep 5

# Maximize and Focus Calligra
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png ga

echo "=== Task setup complete ==="