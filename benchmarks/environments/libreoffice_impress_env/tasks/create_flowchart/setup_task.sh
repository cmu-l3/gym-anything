#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Flowchart Task ==="

sudo -u ga mkdir -p /home/ga/Documents/Presentations

python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page

doc = OpenDocumentPresentation()
page = Page(name="Flowchart")
doc.presentation.addElement(page)
doc.save("/home/ga/Documents/Presentations/flowchart_test.odp")
PYEOF

sudo chown ga:ga /home/ga/Documents/Presentations/flowchart_test.odp

su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/flowchart_test.odp > /tmp/impress_task.log 2>&1 &"

wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 90

su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Create Flowchart Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Create a simple flowchart with:"
echo "    - Start/End ovals"
echo "    - Process rectangles"
echo "    - Decision diamonds"
echo "    - Connectors between shapes"
echo "  Represent a simple process (e.g., making coffee, login flow)"
