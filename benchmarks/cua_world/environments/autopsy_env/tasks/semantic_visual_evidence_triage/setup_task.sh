#!/bin/bash
echo "=== Setting up semantic_visual_evidence_triage task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time

# Clean up any prior runs
rm -f /tmp/visual_triage_result.json /tmp/visual_triage_gt.json
for d in /home/ga/Cases/Visual_Triage_2024*/; do
    [ -d "$d" ] && rm -rf "$d"
done

mkdir -p /home/ga/Reports
chown ga:ga /home/ga/Reports

# Install dependencies if missing (exiftool is required to inject realistic EXIF metadata)
export DEBIAN_FRONTEND=noninteractive
if ! command -v exiftool &> /dev/null; then
    apt-get update -qq && apt-get install -y -qq libimage-exiftool-perl imagemagick > /dev/null 2>&1
fi
if ! command -v convert &> /dev/null; then
    apt-get install -y -qq imagemagick > /dev/null 2>&1
fi

mkdir -p /home/ga/evidence/suspect_photos

# Download realistic images for visual triage (or fallback to color-coded text images if offline)
wget -qO /home/ga/evidence/suspect_photos/IMG_4922.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/New_York_City_Taxi_Cab_in_Motion.jpg/800px-New_York_City_Taxi_Cab_in_Motion.jpg" || convert -size 800x600 xc:yellow -gravity center -pointsize 100 -annotate 0 "TAXI" /home/ga/evidence/suspect_photos/IMG_4922.jpg
wget -qO /home/ga/evidence/suspect_photos/IMG_5011.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5e/Golden_Gate_Bridge_2021.jpg/800px-Golden_Gate_Bridge_2021.jpg" || convert -size 800x600 xc:gray -gravity center -pointsize 100 -annotate 0 "BRIDGE" /home/ga/evidence/suspect_photos/IMG_5011.jpg
wget -qO /home/ga/evidence/suspect_photos/IMG_3301.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/9/90/Labrador_Retriever_portrait.jpg/800px-Labrador_Retriever_portrait.jpg" || convert -size 800x600 xc:brown -gravity center -pointsize 100 -annotate 0 "DOG" /home/ga/evidence/suspect_photos/IMG_3301.jpg
wget -qO /home/ga/evidence/suspect_photos/IMG_8842.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/A_small_cup_of_coffee.JPG/800px-A_small_cup_of_coffee.JPG" || convert -size 800x600 xc:black -gravity center -pointsize 100 -annotate 0 "COFFEE" /home/ga/evidence/suspect_photos/IMG_8842.jpg

# Set exact EXIF dates (These are the timestamps the agent is expected to find in Autopsy)
exiftool -overwrite_original -DateTimeOriginal="2023:10:15 14:30:00" /home/ga/evidence/suspect_photos/IMG_4922.jpg > /dev/null 2>&1
exiftool -overwrite_original -DateTimeOriginal="2023:11:02 09:15:00" /home/ga/evidence/suspect_photos/IMG_5011.jpg > /dev/null 2>&1
exiftool -overwrite_original -DateTimeOriginal="2023:09:20 16:45:00" /home/ga/evidence/suspect_photos/IMG_3301.jpg > /dev/null 2>&1
exiftool -overwrite_original -DateTimeOriginal="2023:12:01 08:00:00" /home/ga/evidence/suspect_photos/IMG_8842.jpg > /dev/null 2>&1

chown -R ga:ga /home/ga/evidence/suspect_photos

# Generate Ground Truth JSON securely hidden from the agent
python3 << 'EOF'
import json, hashlib, os

gt = {}
targets = {
    "IMG_4922.jpg": {"target": "Yellow Taxi", "date": "2023-10-15 14:30:00"},
    "IMG_5011.jpg": {"target": "Bridge", "date": "2023-11-02 09:15:00"}
}

for fname, info in targets.items():
    path = f"/home/ga/evidence/suspect_photos/{fname}"
    if os.path.exists(path):
        with open(path, "rb") as f:
            md5 = hashlib.md5(f.read()).hexdigest()
        gt[info["target"]] = {"md5": md5, "date": info["date"], "filename": fname}

with open('/tmp/visual_triage_gt.json', 'w') as f:
    json.dump(gt, f)
EOF

kill_autopsy

echo "Launching Autopsy..."
launch_autopsy
wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false
while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

if [ "$WELCOME_FOUND" = false ]; then
    kill_autopsy; sleep 2; launch_autopsy
    sleep 30
fi

DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Autopsy" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Prove agent starts from an initialized correct state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="