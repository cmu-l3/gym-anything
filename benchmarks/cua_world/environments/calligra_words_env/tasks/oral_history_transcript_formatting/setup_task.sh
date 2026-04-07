#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Oral History Transcript Formatting Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create necessary directories
install -d -o ga -g ga /home/ga/Documents

# Ensure clean state
kill_calligra_processes
rm -f /home/ga/Documents/mt_st_helens_transcript.odt

# Generate the unformatted raw transcript document using odfpy
python3 << 'PYEOF'
import os
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_p(text):
    doc.text.addElement(P(text=text))

# ── Metadata Block (5 lines to be converted to table) ──
metadata = [
    "Interviewee: Dr. Robert Christiansen, USGS Geologist",
    "Interviewer: Sarah Jenkins, Archival Historian",
    "Date: May 18, 1985 (5-Year Retrospective)",
    "Location: USGS Cascades Volcano Observatory, Vancouver, WA",
    "Collection: Pacific Northwest Historical Archives"
]
for line in metadata:
    add_p(line)

add_p("")

# ── Transcript Body (Q&A Pairs) ──
qa_pairs = [
    ("Q: Dr. Christiansen, take us back to the morning of May 18, 1980. Where were you when the mountain erupted?", 
     "A: I was at the coordination center in Vancouver. We received a radio call from the observation post right before the lateral blast, but the transmission cut off abruptly."),
    ("Q: What was the immediate protocol once the magnitude of the eruption was confirmed?", 
     "A: Communication was our first hurdle. We immediately began coordinating with the Forest Service and local emergency responders to secure the perimeter and track the ash plume."),
    ("Q: Did the lateral blast surprise the geological community?", 
     "A: Yes, the scale and the direction of the blast were unprecedented in our models. We expected a vertical eruption based on historical data, not a massive sector collapse and lateral explosion."),
    ("Q: How did the loss of David Johnston impact the team?", 
     "A: It was devastating. Dave was a brilliant scientist and a close friend. His famous 'Vancouver, Vancouver, this is it!' transmission is etched into all our memories."),
    ("Q: How quickly did you realize the ash cloud would become a global event?", 
     "A: Within hours. Radar showed the plume reaching 80,000 feet, entering the stratosphere. At that altitude, we knew the jet stream would carry it across the continent and eventually around the globe."),
    ("Q: What were the main logistical challenges in the days following the eruption?", 
     "A: Visibility and access. The ash fallout made helicopter flights incredibly dangerous, and roads were completely washed out by the mudflows, the lahars, coming down the Toutle River."),
    ("Q: Looking back five years later, what is the biggest lesson learned from Mount St. Helens?", 
     "A: That we must monitor these volcanoes continuously. You can't just set up instruments when a mountain starts shaking; you need a baseline. That's why the Cascades Volcano Observatory was established."),
    ("Q: How has monitoring technology improved since 1980?", 
     "A: Exponentially. We now have real-time telemetry, better seismic networks, and GPS sensors to measure ground deformation down to the millimeter."),
    ("Q: Can you describe the environment in the red zone today, five years later?", 
     "A: It's a landscape of incredible contrast. The devastation is still stark—miles of blown-down timber—but life is returning much faster than any of us predicted. The biological recovery is astounding."),
    ("Q: Does Mount St. Helens still pose an active threat?", 
     "A: Absolutely. It's still building a lava dome in the crater. While another catastrophic lateral blast is highly unlikely right now, it is still a very active, very dangerous volcano.")
]

for q, a in qa_pairs:
    add_p(q)
    add_p(a)
    add_p("") # spacing between exchanges

doc.save("/home/ga/Documents/mt_st_helens_transcript.odt")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/mt_st_helens_transcript.odt

# Launch Calligra Words with the document
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/mt_st_helens_transcript.odt"

# Wait for application window and maximize
for i in {1..30}; do
    WID=$(get_calligra_window_id)
    if [ -n "$WID" ]; then
        echo "Calligra window found. Maximizing..."
        focus_window "$WID"
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="