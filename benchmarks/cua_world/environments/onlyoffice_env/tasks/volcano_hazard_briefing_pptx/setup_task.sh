#!/bin/bash
set -euo pipefail

echo "=== Setting up Mount Rainier Lahar Hazard Briefing Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create directories
sudo -u ga mkdir -p /home/ga/Documents/Presentations
sudo -u ga mkdir -p /home/ga/Documents/Rainier_Data

# ============================================================================
# Generate Source Data
# ============================================================================

# 1. Historical Data (CSV)
cat << 'EOF' > /home/ga/Documents/Rainier_Data/historical_activity.csv
Event Name,Approximate Age (Years Before Present),Estimated Volume (Cubic Kilometers),Primary River Valley
Osceola Mudflow,5600,3.8,White River
Electron Mudflow,500,0.3,Puyallup River
National Lahar,2200,0.1,Nisqually River
Round Pass Mudflow,2600,0.2,Puyallup River
EOF
chown ga:ga /home/ga/Documents/Rainier_Data/historical_activity.csv

# 2. Demographics Report (TXT)
cat << 'EOF' > /home/ga/Documents/Rainier_Data/risk_demographics.txt
USGS / Pierce County Emergency Management Joint Report
Subject: Mount Rainier Lahar Hazard Demographics

Mount Rainier is considered one of the most dangerous volcanoes in the world due to the massive amount of glacial ice on its slopes and the dense populations in the surrounding river valleys.

Recent demographic analyses indicate that approximately 80,000 people live directly in the lahar hazard zones of the Puyallup and Carbon River valleys. In the event of a major lahar, these residents would have limited time to evacuate to higher ground. The port facilities in Tacoma and regional infrastructure are also at significant risk.
EOF
chown ga:ga /home/ga/Documents/Rainier_Data/risk_demographics.txt

# 3. Hazard Map (JPG)
# Attempt to download a real hazard map, fallback to ImageMagick generation if offline
wget -q -O /home/ga/Documents/Rainier_Data/lahar_evacuation_map.jpg "https://upload.wikimedia.org/wikipedia/commons/e/ec/Mount_Rainier_hazard_map.jpg" || \
    convert -size 800x600 xc:lightblue -fill black -pointsize 36 -gravity center -draw "text 0,0 'MOUNT RAINIER LAHAR EVACUATION MAP\n(Simulated Data)'" /home/ga/Documents/Rainier_Data/lahar_evacuation_map.jpg
chown ga:ga /home/ga/Documents/Rainier_Data/lahar_evacuation_map.jpg

# 4. Draft Presentation (PPTX)
# Generate using python-pptx to ensure it's a valid, clean starting point
cat << 'EOF' > /tmp/create_draft.py
import collections 
import collections.abc
from pptx import Presentation

prs = Presentation()

# Slide 1: Title
title_slide_layout = prs.slide_layouts[0]
slide1 = prs.slides.add_slide(title_slide_layout)
slide1.shapes.title.text = "Mount Rainier Lahar Hazard Briefing"
slide1.placeholders[1].text = "Emergency Management Overview\nPrepared by: Geohazards Team"

# Slide 2: Introduction
bullet_slide_layout = prs.slide_layouts[1]
slide2 = prs.slides.add_slide(bullet_slide_layout)
slide2.shapes.title.text = "Introduction"
tf = slide2.placeholders[1].text_frame
tf.text = "Mount Rainier is an active stratovolcano in Washington State."
p = tf.add_paragraph()
p.text = "Lahars (volcanic mudflows) present the greatest hazard to surrounding communities."
p.level = 1
p2 = tf.add_paragraph()
p2.text = "This briefing outlines historical events, populations at risk, and evacuation zones."
p2.level = 1

prs.save('/home/ga/Documents/Presentations/Rainier_Hazard_Briefing_Draft.pptx')
EOF

su - ga -c "python3 /tmp/create_draft.py"
rm /tmp/create_draft.py

# ============================================================================
# Launch Application
# ============================================================================

# Ensure ONLYOFFICE is not already running
pkill -f "onlyoffice-desktopeditors" || true
sleep 1

# Launch ONLYOFFICE Presentation Editor with the draft
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors /home/ga/Documents/Presentations/Rainier_Hazard_Briefing_Draft.pptx &"

# Wait for window to appear
echo "Waiting for ONLYOFFICE window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "onlyoffice\|desktop editors"; then
        echo "Window found."
        break
    fi
    sleep 1
done

sleep 3 # Give UI time to fully render

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a :ACTIVE: 2>/dev/null || true

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="