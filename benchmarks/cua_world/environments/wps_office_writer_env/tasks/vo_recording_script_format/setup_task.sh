#!/bin/bash
set -euo pipefail

echo "=== Setting up Voice-Over Recording Script Task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_ts

# Create directories
sudo -u ga mkdir -p /home/ga/Documents

# Generate the raw delimited file using python-docx
cat << 'PYEOF' > /tmp/create_raw_dialogue.py
from docx import Document

doc = Document()

# Night of the Living Dead script excerpt structured for game audio pipeline
lines = [
    "NOTLD_001 | JOHNNY | (teasing) | They're coming to get you, Barbra!",
    "NOTLD_002 | BARBRA | (annoyed, frightened) | Stop it! You're ignorant.",
    "NOTLD_003 | JOHNNY | (chuckling) | They're coming for you, Barbra.",
    "NOTLD_004 | BARBRA | (panicking) | Stop it! You're acting like a child.",
    "NOTLD_005 | JOHNNY | (mocking) | They're coming for you! Look, there comes one of them now!",
    "NOTLD_006 | BARBRA | (gasping) | He'll hear you!",
    "NOTLD_007 | JOHNNY | (dismissive) | Here he comes now. I'm getting out of here.",
    "NOTLD_008 | BARBRA | (struggling) | Let go of me! Help!",
    "NOTLD_009 | BEN | (commanding, urgent) | Don't look at it! Get in the house!",
    "NOTLD_010 | BARBRA | (hyperventilating) | What is happening? Who are they?",
    "NOTLD_011 | BEN | (calm but tense) | I don't know. But they're everywhere out there.",
    "NOTLD_012 | BEN | (straining) | Hand me that piece of wood. I need to board this window.",
    "NOTLD_013 | BARBRA | (shocked, whispering) | It's Johnny. They got Johnny.",
    "NOTLD_014 | BEN | (sympathetic but firm) | I'm sorry. We have to secure this place."
]

for line in lines:
    doc.add_paragraph(line)

doc.save("/home/ga/Documents/raw_dialogue.docx")
PYEOF

python3 /tmp/create_raw_dialogue.py
chown ga:ga /home/ga/Documents/raw_dialogue.docx

# Clean up any previous results
rm -f /home/ga/Documents/NOTLD_VO_Script.docx 2>/dev/null || true

# Kill any existing WPS Writer processes to start fresh
pkill -f "wps" 2>/dev/null || true
sleep 2

# Launch WPS Writer with the document
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/raw_dialogue.docx &"

# Wait for application window
wait_for_window "WPS Writer" 30
sleep 5

# Dismiss any popup dialogs (EULA/Updates)
dismiss_wps_dialogs 2>/dev/null || true

# Maximize and focus window
WID=$(get_wps_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="