#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Risk Matrix Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create a basic starting presentation with just a title slide
# We use python to generate a clean ODP to ensure valid structure
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P

doc = OpenDocumentPresentation()

# Slide 1: Title
page = Page(name="TitleSlide")
doc.presentation.addElement(page)

frame = Frame(width="25cm", height="3cm", x="1.5cm", y="2cm")
page.addElement(frame)
textbox = TextBox()
frame.addElement(textbox)
p = P(text="Project Status Report")
textbox.addElement(p)

doc.save("/home/ga/Documents/Presentations/project_status.odp")
PYEOF

sudo chown ga:ga /home/ga/Documents/Presentations/project_status.odp

# Record initial file state
stat -c %Y /home/ga/Documents/Presentations/project_status.odp > /tmp/initial_mtime.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch LibreOffice Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/project_status.odp > /tmp/impress_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 90

# Focus and maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize using wmctrl
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Zoom to fit if needed (Ctrl+0 usually fits to page)
    # safe_xdotool ga :1 key ctrl+0
fi

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="