#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Set Section Backgrounds Task ==="

# Define paths
PRESENTATION_DIR="/home/ga/Documents/Presentations"
PRESENTATION_FILE="$PRESENTATION_DIR/QBR_Q3_2024.odp"

# Ensure directory exists
sudo -u ga mkdir -p "$PRESENTATION_DIR"

# Generate the initial ODP file with Python/odfpy
# We use a python script to ensure the file has valid structure and content
cat << 'PY_SCRIPT' > /tmp/create_qbr.py
import sys
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties
from odf.text import P
from odf.draw import Page, Frame, TextBox

def create_slide(doc, title_text, bullets):
    page = Page(stylename="Standard")
    doc.presentation.addElement(page)
    
    # Title Frame
    title_frame = Frame(width="24cm", height="3cm", x="2cm", y="1cm")
    title_textbox = TextBox()
    title_frame.addElement(title_textbox)
    title_textbox.addElement(P(text=title_text))
    page.addElement(title_frame)
    
    # Content Frame
    content_frame = Frame(width="24cm", height="12cm", x="2cm", y="5cm")
    content_textbox = TextBox()
    content_frame.addElement(content_textbox)
    
    for bullet in bullets:
        content_textbox.addElement(P(text=bullet))
    
    page.addElement(content_frame)

doc = OpenDocumentPresentation()

# Slide 1: Title
create_slide(doc, "Q3 2024 Quarterly Business Review", 
             ["Presented by: Regional Sales Division", "October 15, 2024"])

# Slide 2: Revenue
create_slide(doc, "Revenue Performance Overview", 
             ["Total Revenue: $14.2M (↑ 8% YoY)", "Recurring Revenue: $9.8M (69% of total)", 
              "New Business: $4.4M across 23 new accounts", "Gross Margin: 72.3% (target: 70%)"])

# Slide 3: Regional Breakdown
create_slide(doc, "Revenue Breakdown by Region", 
             ["North America: $6.1M (43%) — exceeded target by 5%", "EMEA: $4.3M (30%) — on target", 
              "Asia-Pacific: $2.8M (20%) — below target by 8%", "Latin America: $1.0M (7%) — new market entry"])

# Slide 4: Challenges
create_slide(doc, "Key Challenges & Risks", 
             ["Extended sales cycles in enterprise segment", "Competitor pricing pressure in mid-market", 
              "Supply chain delays impacting product delivery", "Talent retention: 3 senior AEs departed"])

# Slide 5: Churn
create_slide(doc, "Customer Churn Analysis", 
             ["Overall churn rate: 4.2% (target: <3.5%)", "Primary driver: Lack of integration capabilities", 
              "Secondary: Price sensitivity in SMB segment"])

# Slide 6: Strategy
create_slide(doc, "Q4 Strategic Priorities", 
             ["Priority 1: Close $3.2M pipeline in enterprise", "Priority 2: Launch integration marketplace", 
              "Priority 3: Expand APAC team"])

# Slide 7: Actions
create_slide(doc, "Action Items & Next Steps", 
             ["Complete enterprise pipeline review by Oct 22", "Finalize APAC hiring plan by Oct 30", 
              "Ship integration marketplace beta by Nov 15", "Next QBR scheduled: January 14, 2025"])

doc.save(sys.argv[1])
PY_SCRIPT

echo "Generating QBR presentation..."
python3 /tmp/create_qbr.py "$PRESENTATION_FILE"
sudo chown ga:ga "$PRESENTATION_FILE"

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
stat -c %Y "$PRESENTATION_FILE" > /tmp/initial_file_mtime.txt

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$PRESENTATION_FILE' > /tmp/impress.log 2>&1 &"

# Wait for process
wait_for_process "soffice" 20

# Wait for window
wait_for_window "LibreOffice Impress" 60

# Maximize and focus
WID=$(get_impress_window_id)
if [ -n "$WID" ]; then
    echo "Configuring window $WID..."
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Click on the slide pane (left side) to ensure focus isn't in a weird state
    safe_xdotool ga :1 mousemove 100 300 click 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="