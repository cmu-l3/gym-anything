#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Exhibition Gallery Guide Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
kill_calligra_processes
rm -f /home/ga/Documents/gallery_guide_draft.odt

# ------------------------------------------------------------------
# Create the unformatted gallery guide using odfpy
# ALL content is plain P elements — no heading styles, no bold, etc.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title
add_paragraph("The Impressionist Revolution: Gallery Guide")
add_paragraph("")

# Room 1
add_paragraph("Room 1: The Origins")
add_paragraph("Édouard Manet")
add_paragraph("The Luncheon on the Grass")
add_paragraph("1863, Oil on canvas")
add_paragraph("Manet's large canvas was rejected by the Paris Salon of 1863 and subsequently exhibited at the Salon des Refusés, sparking significant controversy due to its juxtaposition of a female nude with fully dressed men in a contemporary setting.")
add_paragraph("")

# Room 2
add_paragraph("Room 2: The First Exhibition")
add_paragraph("Claude Monet")
add_paragraph("Impression Sunrise")
add_paragraph("1872, Oil on canvas")
add_paragraph("This painting, depicting the port of Le Havre, gave the Impressionist movement its name when critic Louis Leroy used the term derisively in his review of the independent exhibition of 1874.")
add_paragraph("")
add_paragraph("Edgar Degas")
add_paragraph("The Dancing Class")
add_paragraph("1874, Oil on wood")
add_paragraph("Degas focused extensively on the world of ballet, capturing the rigorous training and backstage moments of dancers with innovative, off-center compositions and elevated vantage points.")
add_paragraph("")

# Room 3
add_paragraph("Room 3: Everyday Life")
add_paragraph("Pierre-Auguste Renoir")
add_paragraph("Dance at Le Moulin de la Galette")
add_paragraph("1876, Oil on canvas")
add_paragraph("Renoir masterfully captured the dappled sunlight and vibrant atmosphere of a typical Sunday afternoon at a popular outdoor dance hall in the Montmartre district of Paris.")
add_paragraph("")

# Room 4
add_paragraph("Room 4: The Bridge to Post-Impressionism")
add_paragraph("Paul Cézanne")
add_paragraph("Mont Sainte-Victoire")
add_paragraph("1887, Oil on canvas")
add_paragraph("Cézanne's structured, geometric approach to the landscape of his native Provence laid the groundwork for the transition from 19th-century Impressionism to 20th-century Cubism.")
add_paragraph("")

# Inventory List
add_paragraph("Exhibition Inventory Summary")
add_paragraph("Artist, Title, Year")
add_paragraph("Édouard Manet, The Luncheon on the Grass, 1863")
add_paragraph("Claude Monet, Impression Sunrise, 1872")
add_paragraph("Edgar Degas, The Dancing Class, 1874")
add_paragraph("Pierre-Auguste Renoir, Dance at Le Moulin de la Galette, 1876")
add_paragraph("Paul Cézanne, Mont Sainte-Victoire, 1887")

doc.save("/home/ga/Documents/gallery_guide_draft.odt")
PYEOF

chown ga:ga /home/ga/Documents/gallery_guide_draft.odt

# Launch Calligra Words
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/gallery_guide_draft.odt >/tmp/calligra_words_task.log 2>&1 < /dev/null &"

# Wait for Calligra to appear and maximize it
wait_for_window "Calligra Words" 30 || true
sleep 3
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "=== Task Setup Complete ==="