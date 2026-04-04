#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Embed Functional Spreadsheet Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Generate the initial presentation using odfpy
# We create a 3-slide presentation where Slide 2 is the target
echo "Generating initial ODP file..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties

doc = OpenDocumentPresentation()

# Helper to add a slide with a title
def add_slide(doc, name, title_text):
    page = Page(name=name)
    doc.presentation.addElement(page)
    
    # Title Frame
    frame = Frame(width="25cm", height="3cm", x="1.5cm", y="1cm")
    textbox = TextBox()
    frame.addElement(textbox)
    textbox.addElement(P(text=title_text))
    page.addElement(frame)
    return page

# Slide 1
add_slide(doc, "Overview", "FY2026 Budget Overview")

# Slide 2 (Target for OLE)
add_slide(doc, "Calculator", "Hardware Cost Calculator")

# Slide 3
add_slide(doc, "Timeline", "Approval Timeline")

doc.save("/home/ga/Documents/Presentations/it_budget_draft.odp")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/Presentations/it_budget_draft.odp

# Start LibreOffice Impress
echo "Starting LibreOffice Impress..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/it_budget_draft.odp > /tmp/impress.log 2>&1 &"
    
    # Wait for window
    wait_for_window "LibreOffice Impress" 60
else
    echo "LibreOffice already running, opening file..."
    su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/it_budget_draft.odp &"
fi

# Ensure window is focused and maximized
sleep 5
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any recovery dialogs if they appear (Esc key)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="