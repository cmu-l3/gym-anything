#!/bin/bash
# Setup script for chinook_composer_normalization
# Prepares the specific database copy and calculates ground truth

set -e
echo "=== Setting up Chinook Composer Normalization Task ==="

source /workspace/scripts/task_utils.sh

# Paths
SOURCE_DB="/home/ga/Documents/databases/chinook.db"
WORK_DB="/home/ga/Documents/databases/chinook_normalize.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"
GROUND_TRUTH_FILE="/tmp/composer_ground_truth.json"

# Clean up previous run artifacts
rm -f "$WORK_DB"
rm -f "$EXPORT_DIR/top_composers.csv"
rm -f "$SCRIPTS_DIR/normalize_composers.sql"
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"

# Ensure source DB exists
if [ ! -f "$SOURCE_DB" ]; then
    echo "ERROR: Source Chinook database not found at $SOURCE_DB"
    exit 1
fi

# Create working copy of database
echo "Creating working database copy..."
cp "$SOURCE_DB" "$WORK_DB"
chown ga:ga "$WORK_DB"

# Calculate Ground Truth
# We use Python to parse the current state of the DB and calculate
# exactly how many unique composers and bridge rows should exist
# if the agent performs the split correctly.
echo "Calculating ground truth metrics..."
python3 << PYEOF
import sqlite3
import json

try:
    conn = sqlite3.connect('$WORK_DB')
    c = conn.cursor()
    
    # Fetch all non-null composers
    c.execute("SELECT TrackId, Composer FROM tracks WHERE Composer IS NOT NULL AND Composer != ''")
    rows = c.fetchall()
    
    unique_composers = set()
    total_bridge_rows = 0
    composer_counts = {}
    
    for track_id, composer_str in rows:
        # Agent is instructed to split on comma
        names = [n.strip() for n in composer_str.split(',')]
        names = [n for n in names if n] # Filter empty strings
        
        for name in names:
            unique_composers.add(name)
            total_bridge_rows += 1
            composer_counts[name] = composer_counts.get(name, 0) + 1
            
    # Get top composer for validation
    sorted_composers = sorted(composer_counts.items(), key=lambda x: x[1], reverse=True)
    top_composer = sorted_composers[0] if sorted_composers else ("Unknown", 0)
    
    gt_data = {
        "expected_composer_count": len(unique_composers),
        "expected_bridge_count": total_bridge_rows,
        "top_composer_name": top_composer[0],
        "top_composer_count": top_composer[1],
        "total_tracks_with_composer": len(rows)
    }
    
    with open('$GROUND_TRUTH_FILE', 'w') as f:
        json.dump(gt_data, f, indent=2)
        
    print(f"Ground Truth: {len(unique_composers)} composers, {total_bridge_rows} bridge rows")

except Exception as e:
    print(f"Error calculating ground truth: {e}")
    # Fallback values
    with open('$GROUND_TRUTH_FILE', 'w') as f:
        json.dump({
            "expected_composer_count": 850,
            "expected_bridge_count": 3500,
            "top_composer_name": "Steve Harris",
            "top_composer_count": 0,
            "total_tracks_with_composer": 0
        }, f)
finally:
    if conn: conn.close()
PYEOF

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure DBeaver is running
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver
focus_dbeaver
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="