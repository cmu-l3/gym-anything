#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Academic Poster Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Generate the starting ODP file using python and odfpy
echo "Generating starting presentation..."
cat << 'PYEOF' | python3
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties

doc = OpenDocumentPresentation()

# Content for the 5 slides
slides_content = [
    ("Urban Green Spaces and Community Well-being", "A. Researcher\nDepartment of Urban Studies"),
    ("Introduction", "Rapid urbanization has decreased access to nature.\nThis study examines mental health outcomes in high-density districts."),
    ("Methodology", "We conducted a longitudinal survey of 500 residents.\nData was analyzed using multivariate regression."),
    ("Results", "Positive correlation coefficient (r=0.65) observed between park proximity and reported happiness."),
    ("Conclusion", "Investing in green infrastructure is vital.\nFuture policy implications include zoning for micro-parks.")
]

for i, (title_text, body_text) in enumerate(slides_content):
    page = Page(name=f"Slide{i+1}")
    doc.presentation.addElement(page)

    # Title Frame
    title_frame = Frame(width="25cm", height="3cm", x="1cm", y="1cm")
    title_textbox = TextBox()
    title_frame.addElement(title_textbox)
    title_textbox.addElement(P(text=title_text))
    page.addElement(title_frame)

    # Body Frame
    body_frame = Frame(width="25cm", height="12cm", x="1cm", y="5cm")
    body_textbox = TextBox()
    body_frame.addElement(body_textbox)
    # Split newlines into paragraphs
    for line in body_text.split('\n'):
        body_textbox.addElement(P(text=line))
    page.addElement(body_frame)

output_path = "/home/ga/Documents/Presentations/thesis_draft.odp"
doc.save(output_path)
print(f"Created {output_path}")
PYEOF

# Ensure correct ownership
sudo chown ga:ga /home/ga/Documents/Presentations/thesis_draft.odp

# Launch LibreOffice Impress with the file
echo "Launching LibreOffice Impress..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/thesis_draft.odp > /tmp/impress.log 2>&1 &"
    
    # Wait for window
    wait_for_window "LibreOffice Impress" 30 || echo "Warning: Window wait timeout"
fi

# Focus and maximize
echo "Configuring window..."
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Dismiss any recovery dialogs if they appear (Esc key)
    sleep 2
    safe_xdotool ga :1 key Escape
fi

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="