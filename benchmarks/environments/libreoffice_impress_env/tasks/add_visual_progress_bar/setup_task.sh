#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Visual Progress Bar Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create the starting presentation using python-pptx (easier to generate structure)
# and then convert to ODP using LibreOffice headless
cat > /tmp/create_draft.py << 'PYEOF'
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.enum.text import PP_ALIGN

prs = Presentation()
prs.slide_width = Inches(13.333)  # Widescreen 16:9 approx
prs.slide_height = Inches(7.5)

slides_content = [
    ("New Employee Onboarding", "Welcome to the Team"),
    ("Module 1: Company History", "• Founded in 1985\n• Global expansion in 2000\n• IPO in 2010"),
    ("Module 2: Values & Culture", "• Integrity\n• Innovation\n• Inclusivity"),
    ("Module 3: Tools & Systems", "• Email & Slack\n• Jira & Confluence\n• HR Portal"),
    ("Module 4: Benefits", "• Health Insurance\n• 401k Matching\n• Wellness Stipend"),
    ("Module 5: Next Steps", "• Meet your manager\n• Complete IT setup\n• Team lunch")
]

for title_text, body_text in slides_content:
    slide_layout = prs.slide_layouts[1] # Title and Content
    if title_text == "New Employee Onboarding":
        slide_layout = prs.slide_layouts[0] # Title Slide

    slide = prs.slides.add_slide(slide_layout)
    title = slide.shapes.title
    title.text = title_text
    
    if slide.placeholders[1]:
        body = slide.placeholders[1]
        body.text = body_text

prs.save("/tmp/temp_draft.pptx")
PYEOF

# Run the python script
echo "Generating content..."
python3 /tmp/create_draft.py

# Convert to ODP using LibreOffice headless
echo "Converting to ODP..."
sudo -u ga libreoffice --headless --convert-to odp --outdir /home/ga/Documents/Presentations /tmp/temp_draft.pptx

# Rename if necessary (libreoffice converts to same basename)
if [ -f "/home/ga/Documents/Presentations/temp_draft.odp" ]; then
    mv "/home/ga/Documents/Presentations/temp_draft.odp" "/home/ga/Documents/Presentations/onboarding_draft.odp"
fi

# Cleanup temp
rm -f /tmp/create_draft.py /tmp/temp_draft.pptx

# Verify file exists
if [ ! -f "/home/ga/Documents/Presentations/onboarding_draft.odp" ]; then
    echo "ERROR: Failed to create input file"
    exit 1
fi

sudo chown ga:ga /home/ga/Documents/Presentations/onboarding_draft.odp

# Launch LibreOffice Impress with the file
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/onboarding_draft.odp > /tmp/impress_task.log 2>&1 &"

# Wait for process
wait_for_process "soffice" 15

# Wait for window
if ! wait_for_window "LibreOffice Impress" 90; then
    echo "WARNING: Window detection timed out, trying to proceed..."
fi

# Ensure focus
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    safe_xdotool ga :1 key F11
    sleep 0.5
    # Click to focus content area
    su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
fi

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="