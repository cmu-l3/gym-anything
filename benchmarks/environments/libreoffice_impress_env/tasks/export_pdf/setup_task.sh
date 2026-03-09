#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Export PDF Task ==="

sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create a simple presentation to export
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page

doc = OpenDocumentPresentation()

for i in range(3):
    page = Page(name=f"Slide{i+1}")
    doc.presentation.addElement(page)

doc.save("/home/ga/Documents/Presentations/export_test.odp")
PYEOF

sudo chown ga:ga /home/ga/Documents/Presentations/export_test.odp

su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/export_test.odp > /tmp/impress_task.log 2>&1 &"

wait_for_process "soffice" 15
wait_for_window "LibreOffice Impress" 90

su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Export PDF Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Go to File → Export as PDF"
echo "  2. Keep default settings or adjust quality"
echo "  3. Save as 'export_test.pdf' in Documents/Presentations/"
