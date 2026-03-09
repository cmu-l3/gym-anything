#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Apply Template Task ==="

sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create a basic presentation with content
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties

# Create presentation
doc = OpenDocumentPresentation()

# Add 3 slides with basic content
for i in range(3):
    page = Page(name=f"Slide{i+1}")
    doc.presentation.addElement(page)
    
    # Add a text frame (title area)
    frame = Frame(width="720pt", height="56pt", x="56pt", y="42pt")
    page.addElement(frame)
    
    textbox = TextBox()
    frame.addElement(textbox)
    
    p = P(text=f"Slide {i+1} Title")
    textbox.addElement(p)

doc.save("/home/ga/Documents/Presentations/template_test.odp")
print("Created test presentation")
PYEOF

sudo chown ga:ga /home/ga/Documents/Presentations/template_test.odp

# Launch Impress with the presentation
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/template_test.odp > /tmp/impress_task.log 2>&1 &"

wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 90

su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key F11
    sleep 0.5
fi

echo "=== Apply Template Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open the Slide menu"
echo "  2. Select 'Slide Design' or 'Properties'"
echo "  3. Choose a template from the available templates"
echo "  4. Apply it to all slides"
