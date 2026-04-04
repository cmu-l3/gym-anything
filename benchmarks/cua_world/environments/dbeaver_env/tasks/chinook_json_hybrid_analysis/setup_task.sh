#!/bin/bash
set -e
echo "=== Setting up Chinook JSON Hybrid Analysis Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure DBeaver is running and ready
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 15
fi

# Maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 3. Prepare Directories
mkdir -p /home/ga/Documents/imports
mkdir -p /home/ga/Documents/exports
mkdir -p /home/ga/Documents/scripts
chown -R ga:ga /home/ga/Documents

# 4. Generate the "Track Features" CSV file with JSON blobs
# We use Python to generate valid JSON and random data
echo "Generating track_features.csv..."

cat > /tmp/generate_data.py << 'EOF'
import sqlite3
import json
import random
import csv
import os

# Connect to Chinook to get valid Track IDs to ensure FK validity
db_path = "/home/ga/Documents/databases/chinook.db"
track_ids = []

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        # Get 100 random track IDs
        cursor.execute("SELECT TrackId FROM tracks ORDER BY RANDOM() LIMIT 100")
        track_ids = [r[0] for r in cursor.fetchall()]
        conn.close()
    except Exception as e:
        print(f"Error accessing DB: {e}")

# Fallback if DB access fails
if not track_ids:
    track_ids = list(range(1, 101))

keys = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']
modes = ['Major', 'Minor']

output_file = '/home/ga/Documents/imports/track_features.csv'

with open(output_file, 'w', newline='', encoding='utf-8') as f:
    # Use pipe delimiter, no quoting (common messy data scenario)
    writer = csv.writer(f, delimiter='|', quoting=csv.QUOTE_NONE, escapechar='\\')
    
    # Header
    writer.writerow(['TrackId', 'Features'])
    
    for tid in track_ids:
        # Generate random audio features
        bpm = random.randint(60, 180)
        key = f"{random.choice(keys)} {random.choice(modes)}"
        danceability = round(random.uniform(0.3, 0.95), 2)
        
        # Ensure enough "High Energy" tracks for the report (BPM > 130, Dance > 0.7)
        if random.random() < 0.25:
            bpm = random.randint(131, 170)
            danceability = round(random.uniform(0.71, 0.95), 2)
            
        features = {
            "bpm": bpm,
            "key": key,
            "danceability": danceability,
            "energy": round(random.uniform(0.5, 1.0), 2),
            "analysis_version": "v1.2"
        }
        
        # Write: ID | JSON_STRING
        writer.writerow([tid, json.dumps(features)])

print(f"Generated {len(track_ids)} rows in {output_file}")
EOF

# Run generator
python3 /tmp/generate_data.py
chown ga:ga /home/ga/Documents/imports/track_features.csv

# 5. Clean up previous artifacts (if any)
rm -f /home/ga/Documents/exports/high_energy_tracks.csv
rm -f /home/ga/Documents/scripts/json_analysis.sql

# 6. Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="