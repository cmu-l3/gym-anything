#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Add Animations Task ==="

sudo -u ga mkdir -p /home/ga/Documents/Presentations

python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page

doc = OpenDocumentPresentation()

for i in range(2):
    page = Page(name=f"Slide{i+1}")
    doc.presentation.addElement(page)

doc.save("/home/ga/Documents/Presentations/animation_test.odp")
PYEOF

sudo chown ga:ga /home/ga/Documents/Presentations/animation_test.odp

su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/animation_test.odp > /tmp/impress_task.log 2>&1 &"

wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 90

su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Add Animations Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Add slide transitions to both slides"
echo "  2. Add object animations if objects are present"
