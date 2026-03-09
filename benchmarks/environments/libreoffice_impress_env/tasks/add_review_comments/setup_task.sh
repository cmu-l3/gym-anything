#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Add Review Comments Task ==="

# Define paths
DOCS_DIR="/home/ga/Documents"
PRES_DIR="$DOCS_DIR/Presentations"
FILE_PATH="$PRES_DIR/marketing_strategy.odp"
NOTES_PATH="$DOCS_DIR/feedback_notes.txt"

# Ensure directories exist
sudo -u ga mkdir -p "$PRES_DIR"

# Generate ODP file using python and odfpy (available in env)
echo "Generating presentation file..."
python3 -c "
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties

doc = OpenDocumentPresentation()

# Define slides (Title, Body text)
slides_info = [
    ('Q3 Marketing Strategy - 2024', 'Confidential Internal Draft\nPrepared by: Marketing Team'),
    ('Q3 Goals', '• Increase Brand Awareness by 20%\n• Boost Lead Gen by 15%\n• Expand into new verticals'),
    ('Budget Breakdown', 'PPC: $50,000\nSocial Media: $30,000\nEvents: $20,000\nContent: $15,000'),
    ('Channel Performance', 'LinkedIn: +15% YoY\nTwitter: +5% YoY\nInstagram: +10% YoY'),
    ('Next Steps', '• Approve budget allocations\n• Launch Q3 campaigns\n• Weekly performance reviews')
]

for i, (title_text, body_text) in enumerate(slides_info):
    page = Page(name=f'Slide{i+1}')
    doc.presentation.addElement(page)
    
    # Title Frame
    t_frame = Frame(width='24cm', height='3cm', x='2cm', y='2cm')
    t_box = TextBox()
    t_frame.addElement(t_box)
    t_box.addElement(P(text=title_text))
    page.addElement(t_frame)
    
    # Body Frame
    b_frame = Frame(width='24cm', height='12cm', x='2cm', y='6cm')
    b_box = TextBox()
    b_frame.addElement(b_box)
    for line in body_text.split('\n'):
        b_box.addElement(P(text=line))
    page.addElement(b_frame)

doc.save('$FILE_PATH')
"

# Set permissions
chown ga:ga "$FILE_PATH"

# Create feedback notes
echo "Creating feedback notes..."
cat > "$NOTES_PATH" << EOF
MARKETING STRATEGY REVIEW NOTES
===============================

Please review the 'marketing_strategy.odp' presentation and add the following comments (Insert > Comment) to the specific slides so the team knows what to fix.

1. On Slide 2 ('Q3 Goals'):
   Add comment: "Target audience needs to be more specific here."

2. On Slide 3 ('Budget Breakdown'):
   Add comment: "Please double-check the 'Social Media' allocation."

3. On Slide 4 ('Channel Performance'):
   Add comment: "Add the TikTok engagement metrics to this chart."

Please save the file when you are finished.
EOF
chown ga:ga "$NOTES_PATH"

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Launch applications
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$FILE_PATH' > /tmp/impress.log 2>&1 &"

echo "Launching Text Editor..."
su - ga -c "DISPLAY=:1 gedit '$NOTES_PATH' > /tmp/gedit.log 2>&1 &"

# Wait for Impress window
wait_for_window "LibreOffice Impress" 60

# Maximize Impress window
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Focusing and maximizing Impress..."
    focus_window "$wid"
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss any recovery dialogs or tips if they appear
    sleep 2
    safe_xdotool ga :1 key Escape 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="