#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Agenda Summary Slide Task ==="

# 1. Create task directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# 2. Generate the initial presentation using odfpy
# We create a 6-slide presentation: Title + 5 Content slides
echo "Generating initial presentation..."
cat << 'PYEOF' | python3
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties

def create_slide(doc, name, title_text, bullets=[]):
    page = Page(name=name)
    doc.presentation.addElement(page)
    
    # Title Frame
    title_frame = Frame(width="25cm", height="3cm", x="1.5cm", y="1cm")
    page.addElement(title_frame)
    title_box = TextBox()
    title_frame.addElement(title_box)
    title_box.addElement(P(text=title_text))
    
    # Content Frame
    if bullets:
        content_frame = Frame(width="25cm", height="12cm", x="1.5cm", y="5cm")
        page.addElement(content_frame)
        content_box = TextBox()
        content_frame.addElement(content_box)
        for bullet in bullets:
            content_box.addElement(P(text=bullet))

doc = OpenDocumentPresentation()

# Slide 1: Title
create_slide(doc, "Slide1", "Q3 Strategic Initiatives", ["Presented by: PMO Office", "Date: October 2024"])

# Slide 2
create_slide(doc, "Slide2", "Cloud Migration Timeline", ["Phase 1: Assessment completed", "Phase 2: Migration starting Nov 1", "Risk: Legacy database compatibility"])

# Slide 3
create_slide(doc, "Slide3", "Budget Variance Analysis", ["Q3 Spend: $1.2M (vs $1.0M budget)", "Overhead: +15% due to licensing", "Action: Freeze non-essential hiring"])

# Slide 4
create_slide(doc, "Slide4", "Talent Acquisition Pipeline", ["Open Roles: 12", "Offers Accepted: 5", "Time to Fill: 45 days (avg)"])

# Slide 5
create_slide(doc, "Slide5", "Security Audit Findings", ["Critical Vulnerabilities: 0", "High Risks: 2 (Patched)", "Compliance: SOC2 Type II Ready"])

# Slide 6
create_slide(doc, "Slide6", "Vendor Renewal Status", ["AWS: Renewed for 3 years", "Salesforce: Negotiation in progress", "Slack: Upgrading to Enterprise Grid"])

doc.save("/home/ga/Documents/Presentations/strategic_initiatives.odp")
print("Presentation generated successfully.")
PYEOF

# Ensure permissions
sudo chown ga:ga /home/ga/Documents/Presentations/strategic_initiatives.odp

# 3. Record start time and initial state
date +%s > /tmp/task_start_time.txt
# Record initial slide count (6)
echo "6" > /tmp/initial_slide_count.txt

# 4. Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/strategic_initiatives.odp > /tmp/impress_task.log 2>&1 &"

# 5. Wait for application to be ready
wait_for_window "LibreOffice Impress" 60 || echo "WARNING: Window wait timeout"

# 6. Ensure window is focused and maximized
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Focusing window ID: $wid"
    focus_window "$wid"
    # Maximize
    safe_xdotool ga :1 key F11 2>/dev/null || true
    sleep 1
    # Click to ensure focus on the slide pane or main view
    safe_xdotool ga :1 mousemove 600 600 click 1
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="