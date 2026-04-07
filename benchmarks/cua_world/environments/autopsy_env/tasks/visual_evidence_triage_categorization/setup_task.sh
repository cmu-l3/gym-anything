#!/bin/bash
# Setup script for visual_evidence_triage_categorization task

echo "=== Setting up visual_evidence_triage_categorization task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/visual_triage_result.json /tmp/visual_triage_gt.json \
      /tmp/visual_triage_start_time 2>/dev/null || true

for d in /home/ga/Cases/Aviation_Smuggling_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Download real dataset (Aircraft vs Cars) ──────────────────────────────────
EVIDENCE_DIR="/home/ga/evidence/vehicle_photos"
rm -rf "$EVIDENCE_DIR" 2>/dev/null || true
mkdir -p "$EVIDENCE_DIR"

echo "Downloading real photographic dataset..."
python3 << 'PYEOF'
import os
import json
import urllib.request
import uuid

EVIDENCE_DIR = "/home/ga/evidence/vehicle_photos"

# Wikipedia commons URLs for real-world images
IMAGES = [
    # Airplanes (Targets)
    {"url": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a9/Boeing_747-8_first_flight_edit1.jpg/800px-Boeing_747-8_first_flight_edit1.jpg", "is_aircraft": True},
    {"url": "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/F-22_Raptor_edit1.jpg/800px-F-22_Raptor_edit1.jpg", "is_aircraft": True},
    {"url": "https://upload.wikimedia.org/wikipedia/commons/thumb/9/90/Airbus_A380_over_Toulouse.jpg/800px-Airbus_A380_over_Toulouse.jpg", "is_aircraft": True},
    {"url": "https://upload.wikimedia.org/wikipedia/commons/thumb/c/cb/Cessna_172S_Skyhawk_SP_in_flight.jpg/800px-Cessna_172S_Skyhawk_SP_in_flight.jpg", "is_aircraft": True},
    {"url": "https://upload.wikimedia.org/wikipedia/commons/thumb/d/d7/SR-71_in_flight.jpg/800px-SR-71_in_flight.jpg", "is_aircraft": True},
    
    # Cars (Decoys)
    {"url": "https://upload.wikimedia.org/wikipedia/commons/thumb/4/41/2018_Ford_Mustang_GT_5.0.jpg/800px-2018_Ford_Mustang_GT_5.0.jpg", "is_aircraft": False},
    {"url": "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1b/2019_Toyota_Corolla_Icon_Tech_VVT-i_Hybrid_1.8.jpg/800px-2019_Toyota_Corolla_Icon_Tech_VVT-i_Hybrid_1.8.jpg", "is_aircraft": False},
    {"url": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a4/2019_Volkswagen_Golf_GTI_Performance_TSI_S-A_2.0_Front.jpg/800px-2019_Volkswagen_Golf_GTI_Performance_TSI_S-A_2.0_Front.jpg", "is_aircraft": False},
    {"url": "https://upload.wikimedia.org/wikipedia/commons/thumb/7/7b/2015_Honda_Civic_SE_1.8_Front.jpg/800px-2015_Honda_Civic_SE_1.8_Front.jpg", "is_aircraft": False},
    {"url": "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/2020_Porsche_911_Carrera_S_3.0_Front.jpg/800px-2020_Porsche_911_Carrera_S_3.0_Front.jpg", "is_aircraft": False}
]

target_aircraft_files = []
decoy_car_files = []

for idx, item in enumerate(IMAGES):
    # Use random hex names so the agent cannot cheat by reading filenames
    random_filename = f"{uuid.uuid4().hex[:8]}.jpg"
    dest_path = os.path.join(EVIDENCE_DIR, random_filename)
    
    try:
        req = urllib.request.Request(item["url"], headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=15) as response, open(dest_path, 'wb') as out_file:
            out_file.write(response.read())
            
        if item["is_aircraft"]:
            target_aircraft_files.append(random_filename)
        else:
            decoy_car_files.append(random_filename)
            
        print(f"Downloaded: {random_filename} (Aircraft: {item['is_aircraft']})")
    except Exception as e:
        print(f"Failed to download {item['url']}: {e}")

# Save ground truth explicitly
gt = {
    "total_images": len(target_aircraft_files) + len(decoy_car_files),
    "target_aircraft": target_aircraft_files,
    "decoy_cars": decoy_car_files
}

with open("/tmp/visual_triage_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth saved: {len(target_aircraft_files)} aircraft, {len(decoy_car_files)} cars.")
PYEOF

chown -R ga:ga "$EVIDENCE_DIR"

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/visual_triage_start_time
echo "Task start time recorded: $(cat /tmp/visual_triage_start_time)"

# ── Kill any running Autopsy and Relaunch ─────────────────────────────────────
kill_autopsy

echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy process to start..."
wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected after ${WELCOME_ELAPSED}s"
        WELCOME_FOUND=true
        break
    fi
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy died, relaunching at ${WELCOME_ELAPSED}s..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear within ${WELCOME_TIMEOUT}s"
    kill_autopsy
    sleep 2
    launch_autopsy
    # Additional wait buffer
    sleep 60
fi

# Dismiss any popup dialogs
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot showing Autopsy ready
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="