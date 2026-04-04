#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Bilingual Safety Alignment Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Record task start timestamp for verifier
date +%s > /tmp/task_start_time.txt
chown ga:ga /tmp/task_start_time.txt 2>/dev/null || true

# Generate the raw sequential document using python-docx
# This ensures a consistent starting state every time
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Main Title
title = doc.add_paragraph("Forklift Safety / Seguridad de Montacargas")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
for run in title.runs:
    run.bold = True
    run.font.size = Pt(16)

doc.add_paragraph("")

# English Section
h_en = doc.add_paragraph("English Rules")
h_en.style = "Heading 1"

rules_en = [
    "Get training before operating a forklift.",
    "Buckle up. Use the seatbelt every time.",
    "No riders. Do not carry passengers.",
    "Keep forks low when traveling.",
    "Look behind you before backing up.",
    "Park safely. Lower forks, neutralize controls, set brake.",
    "Slow down at intersections and horn."
]

for rule in rules_en:
    p = doc.add_paragraph(rule, style='List Number')

doc.add_paragraph("")

# Spanish Section
h_es = doc.add_paragraph("Reglas en Español")
h_es.style = "Heading 1"

rules_es = [
    "Reciba capacitación antes de operar un montacargas.",
    "Use el cinturón de seguridad siempre.",
    "No lleve pasajeros. Prohibido llevar a otros.",
    "Mantenga las horquillas bajas al viajar.",
    "Mire hacia atrás antes de retroceder.",
    "Estaciónese seguramente. Baje las horquillas, neutralice los controles, ponga el freno.",
    "Baje la velocidad en intersecciones y use la bocina."
]

for rule in rules_es:
    p = doc.add_paragraph(rule, style='List Number')

doc.save("/home/ga/Documents/forklift_safety_raw.docx")
print("Created /home/ga/Documents/forklift_safety_raw.docx")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/forklift_safety_raw.docx
chmod 666 /home/ga/Documents/forklift_safety_raw.docx

# Launch LibreOffice Writer with the document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/forklift_safety_raw.docx > /tmp/writer_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/writer_task.log
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Writer" 90; then
    wait_for_window "forklift" 30 || true
fi

# Maximize window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    echo "Maximizing window $wid..."
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz
    focus_window "$wid"
fi

# Dismiss any "What's New" infobar or tooltips
safe_xdotool ga :1 key Escape
sleep 0.5

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="