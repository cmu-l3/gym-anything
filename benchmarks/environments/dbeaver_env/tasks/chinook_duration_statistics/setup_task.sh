#!/bin/bash
# Setup script for chinook_duration_statistics task

set -e
echo "=== Setting up Chinook Duration Statistics Task ==="

source /workspace/scripts/task_utils.sh

# Directories
DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"
CHINOOK_DB="$DB_DIR/chinook.db"

# Ensure directories exist and are clean
mkdir -p "$DB_DIR" "$EXPORT_DIR" "$SCRIPTS_DIR"
rm -f "$EXPORT_DIR/genre_duration_stats.csv"
rm -f "$EXPORT_DIR/duration_outliers.csv"
rm -f "$SCRIPTS_DIR/duration_stats.sql"

# Ensure Chinook database exists (setup_dbeaver.sh usually handles this, but we force check)
if [ ! -f "$CHINOOK_DB" ]; then
    echo "Restoring Chinook database..."
    if [ -f "/workspace/data/chinook.db" ]; then
        cp "/workspace/data/chinook.db" "$CHINOOK_DB"
    else
        # Fallback download
        wget -q -O "$CHINOOK_DB" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
    fi
fi
chmod 644 "$CHINOOK_DB"
chown ga:ga "$CHINOOK_DB"

# Generate Ground Truth Data using Python
# This calculates the exact stats the agent is expected to find
echo "Generating ground truth data..."
python3 << 'PYEOF'
import sqlite3
import json
import math

db_path = "/home/ga/Documents/databases/chinook.db"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
c = conn.cursor()

# Get Genre Stats
stats = {}
rows = c.execute("""
    SELECT g.Name as GenreName, t.Milliseconds
    FROM tracks t
    JOIN genres g ON t.GenreId = g.GenreId
""").fetchall()

genre_data = {}
for r in rows:
    g = r['GenreName']
    dur = r['Milliseconds'] / 1000.0 # Convert to seconds
    if g not in genre_data:
        genre_data[g] = []
    genre_data[g].append(dur)

genre_stats = []
outliers = []

for g, durations in genre_data.items():
    count = len(durations)
    if count < 10:
        continue
    
    durations.sort()
    
    # Mean
    mean = sum(durations) / count
    
    # Median
    if count % 2 == 1:
        median = durations[count // 2]
    else:
        median = (durations[count // 2 - 1] + durations[count // 2]) / 2.0
        
    # StdDev (Population)
    variance = sum([((x - mean) ** 2) for x in durations]) / count
    stddev = math.sqrt(variance)
    
    # Coeff of Variation
    cv = (stddev / mean) * 100 if mean > 0 else 0
    
    genre_stats.append({
        "GenreName": g,
        "TrackCount": count,
        "AvgDurationSec": round(mean, 1),
        "MedianDurationSec": round(median, 1),
        "StdDevDurationSec": round(stddev, 1),
        "CoeffOfVariation": round(cv, 1)
    })
    
    # Find Outliers (|z| > 2)
    for i, dur in enumerate(durations):
        if stddev > 0:
            z = (dur - mean) / stddev
            if abs(z) > 2.0:
                outliers.append({
                    "GenreName": g,
                    "DurationSec": round(dur, 1),
                    "ZScore": round(z, 2),
                    "OutlierType": "SHORT" if z < 0 else "LONG"
                })

# Sort stats by CV desc
genre_stats.sort(key=lambda x: x['CoeffOfVariation'], reverse=True)

# Save ground truth
gt = {
    "genre_stats": genre_stats,
    "outliers": outliers,
    "total_outliers": len(outliers)
}

with open('/tmp/chinook_stats_ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth generated. Found {len(genre_stats)} genres and {len(outliers)} outliers.")
PYEOF

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start DBeaver if not running
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "dbeaver"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize DBeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "DBeaver" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="