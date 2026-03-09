#!/bin/bash
set -e
echo "=== Setting up Edit Slide Master Branding task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/Presentations
chown -R ga:ga /home/ga/Documents

# 1. Create the starting presentation using python-pptx
# We use python-pptx to generate a clean, realistic starting state
echo "Generating starting presentation..."
python3 << 'PYEOF'
import sys
try:
    from pptx import Presentation
    from pptx.util import Inches, Pt
except ImportError:
    print("python-pptx not found")
    sys.exit(1)

prs = Presentation()
# Set 16:9 aspect ratio
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

# Slide 1: Title
slide1 = prs.slides.add_slide(prs.slide_layouts[0])
if slide1.shapes.title:
    slide1.shapes.title.text = "Quarterly Board Meeting – Q4 2024"
if len(slide1.placeholders) > 1:
    slide1.placeholders[1].text = "Community Health Alliance – December 12, 2024"

# Slide 2: Program Updates
slide2 = prs.slides.add_slide(prs.slide_layouts[1])
if slide2.shapes.title:
    slide2.shapes.title.text = "Program Updates"
if len(slide2.placeholders) > 1:
    tf = slide2.placeholders[1].text_frame
    tf.text = "Maternal health outreach expanded to 3 new counties"
    p = tf.add_paragraph()
    p.text = "Youth mentorship program enrollment up 22% year-over-year"
    p = tf.add_paragraph()
    p.text = "Senior wellness initiative received state accreditation"
    p = tf.add_paragraph()
    p.text = "Food security partnership with Regional Food Bank renewed for 2025"

# Slide 3: Budget Overview
slide3 = prs.slides.add_slide(prs.slide_layouts[1])
if slide3.shapes.title:
    slide3.shapes.title.text = "Budget Overview"
if len(slide3.placeholders) > 1:
    tf = slide3.placeholders[1].text_frame
    tf.text = "Total revenue YTD: $2.4M (103% of target)"
    p = tf.add_paragraph()
    p.text = "Federal grants: $1.1M received, $340K pending"
    p = tf.add_paragraph()
    p.text = "Operating expenses at 94% of budget"
    p = tf.add_paragraph()
    p.text = "Reserve fund balance: $425K (18% of annual budget)"

# Slide 4: Action Items
slide4 = prs.slides.add_slide(prs.slide_layouts[1])
if slide4.shapes.title:
    slide4.shapes.title.text = "Action Items"
if len(slide4.placeholders) > 1:
    tf = slide4.placeholders[1].text_frame
    tf.text = "Board vote on 2025 strategic plan – January meeting"
    p = tf.add_paragraph()
    p.text = "Executive Director performance review – due January 15"
    p = tf.add_paragraph()
    p.text = "Annual fundraising gala logistics committee – volunteers needed"
    p = tf.add_paragraph()
    p.text = "Q1 2025 program budget submissions – due December 30"

prs.save("/home/ga/Documents/Presentations/board_meeting.pptx")
print("Presentation generated successfully")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/Presentations/board_meeting.pptx

# 2. Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
# Kill any existing instances
pkill -f soffice 2>/dev/null || true
sleep 1

# Launch with file
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/board_meeting.pptx > /tmp/impress.log 2>&1 &"

# 3. Wait for window
echo "Waiting for Impress window..."
source /workspace/scripts/task_utils.sh
wait_for_window "LibreOffice Impress" 60 || wait_for_window "board_meeting" 60

# 4. Maximize and focus
echo "Configuring window..."
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Dismiss any "Tip of the Day" or recovery dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# 5. Capture initial state
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="