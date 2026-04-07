#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Music Catalog Royalty Reconciliation Task ==="

# Record start time for anti-gaming
echo $(date +%s) > /tmp/task_start_ts

# Cleanup environment
cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/q3_streaming_export.csv"

# Generate a highly realistic streaming dataset (500 records)
cat > /tmp/create_streaming_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import sys
import random

output_path = sys.argv[1]
random.seed(42) # Deterministic seed so verifier can calculate exact ground truth

platforms = ["Spotify", "Apple Music", "Tidal", "Amazon Music", "YouTube"]

# Generate 100 realistic indie track names
adjectives = ["Neon", "Midnight", "Electric", "Retro", "Digital", "Cyber", "Crystal", "Holographic", "Virtual", "Synth"]
nouns = ["Horizon", "Skyline", "Dreams", "Nights", "Echo", "Heart", "Vibes", "Wave", "City", "Sunset"]
artists = ["The Midnight Echo", "Synthwave Surfers", "Neon Horizon", "Pixelated Minds", "Aesthetic Vibes", "Cybernetic Youth", "Timecop1983", "FM-84", "Gunship", "The Strike"]

tracks = []
for i in range(100):
    title = f"{random.choice(adjectives)} {random.choice(nouns)}"
    if random.random() > 0.8:
        title += " (Remix)"
    artist = random.choice(artists)
    tracks.append((f"TRK-{1000+i}", title, artist))

# Write to CSV
with open(output_path, 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerow(["Track_ID", "Track_Name", "Artist", "Platform", "Stream_Count"])
    
    for track_id, title, artist in tracks:
        for platform in platforms:
            # Realistic streaming distributions (Spotify/YouTube high volume, Tidal low volume)
            if platform == "Spotify":
                streams = int(random.lognormvariate(11, 1.5))
            elif platform == "YouTube":
                streams = int(random.lognormvariate(12, 1.8))
            elif platform == "Apple Music":
                streams = int(random.lognormvariate(10.5, 1.2))
            elif platform == "Amazon Music":
                streams = int(random.lognormvariate(9.5, 1.0))
            else: # Tidal
                streams = int(random.lognormvariate(8.5, 0.8))
                
            # Ensure minimums
            streams = max(150, streams)
            writer.writerow([track_id, title, artist, platform, streams])

print(f"Generated 500 streaming records at {output_path}")
PYEOF

sudo -u ga python3 /tmp/create_streaming_data.py "$CSV_PATH"

# Open the CSV in ONLYOFFICE
echo "Launching ONLYOFFICE..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice.log 2>&1 &"

# Wait for application to start
wait_for_window "ONLYOFFICE" 30
sleep 5

# Maximize and focus
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="