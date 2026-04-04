#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bulk Text Replace Task ==="

sudo -u ga mkdir -p /home/ga/Documents/Presentations

python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P

doc = OpenDocumentPresentation()

# Create 3 slides with the word "Company" multiple times
for i in range(3):
    page = Page(name=f"Slide{i+1}")
    doc.presentation.addElement(page)
    
    frame = Frame(width="720pt", height="56pt", x="56pt", y="42pt")
    page.addElement(frame)
    
    textbox = TextBox()
    frame.addElement(textbox)
    
    p = P(text=f"Company Overview Slide {i+1} - Company Name")
    textbox.addElement(p)

doc.save("/home/ga/Documents/Presentations/replace_test.odp")
PYEOF

sudo chown ga:ga /home/ga/Documents/Presentations/replace_test.odp

su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/replace_test.odp > /tmp/impress_task.log 2>&1 &"

wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 90

su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Bulk Text Replace Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open Find & Replace dialog (Ctrl+H)"
echo "  2. Find: 'Company'"
echo "  3. Replace with: 'Organization'"
echo "  4. Click 'Replace All'"
