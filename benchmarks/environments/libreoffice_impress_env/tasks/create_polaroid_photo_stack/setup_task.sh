#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Polaroid Photo Stack Task ==="

# 1. Prepare Directories
ASSETS_DIR="/home/ga/Documents/Assets"
PRES_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$ASSETS_DIR"
sudo -u ga mkdir -p "$PRES_DIR"

# 2. Create Dummy Assets (Images) using ImageMagick
# We create 3 distinct images with text so they are recognizable
echo "Generating asset images..."
sudo -u ga convert -size 400x300 xc:lightblue -font DejaVu-Sans -pointsize 30 -gravity center -draw "text 0,0 'Team Brainstorm'" "$ASSETS_DIR/team_brainstorm.jpg"
sudo -u ga convert -size 400x300 xc:lightgreen -font DejaVu-Sans -pointsize 30 -gravity center -draw "text 0,0 'Office Lunch'" "$ASSETS_DIR/office_lunch.jpg"
sudo -u ga convert -size 400x300 xc:lightpink -font DejaVu-Sans -pointsize 30 -gravity center -draw "text 0,0 'Design Review'" "$ASSETS_DIR/design_review.jpg"

# 3. Create Starting Presentation (culture_deck.odp)
# Slide 1: Title, Slide 2: Blank
echo "Creating initial presentation..."
cat << 'PYEOF' > /tmp/create_pres.py
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P

doc = OpenDocumentPresentation()

# Slide 1: Title
page1 = Page(name="Title")
doc.presentation.addElement(page1)
frame = Frame(width="20cm", height="3cm", x="4cm", y="7cm")
textbox = TextBox()
textbox.addElement(P(text="Agency Culture"))
frame.addElement(textbox)
page1.addElement(frame)

# Slide 2: Blank (Target)
page2 = Page(name="Photos")
doc.presentation.addElement(page2)

doc.save("/home/ga/Documents/Presentations/culture_deck.odp")
PYEOF

python3 /tmp/create_pres.py
sudo chown ga:ga "$PRES_DIR/culture_deck.odp"
rm /tmp/create_pres.py

# 4. Record Initial State (File stats)
stat "$PRES_DIR/culture_deck.odp" > /tmp/initial_file_stat.txt
date +%s > /tmp/task_start_time.txt

# 5. Launch Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress $PRES_DIR/culture_deck.odp > /tmp/impress.log 2>&1 &"

# 6. Wait for window and maximize
wait_for_window "LibreOffice Impress" 60
WID=$(get_impress_window_id)

if [ -n "$WID" ]; then
    echo "Focusing and maximizing window $WID..."
    focus_window "$WID"
    # Maximize
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Click center to focus slide view (dismiss sidebar focus if any)
    safe_xdotool ga :1 mousemove 960 540 click 1
fi

# 7. Take Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="