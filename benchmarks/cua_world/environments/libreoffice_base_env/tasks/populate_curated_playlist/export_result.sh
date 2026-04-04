#!/bin/bash
echo "=== Exporting populate_curated_playlist result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application was running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# Ensure ODB exists
ODB_PATH="/home/ga/chinook.odb"
if [ ! -f "$ODB_PATH" ]; then
    echo "ERROR: chinook.odb not found"
    cat > /tmp/task_result.json << EOF
{
    "error": "Database file missing",
    "app_was_running": $APP_RUNNING,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF
    exit 0
fi

# Check modification time
ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Extract database script to analyze content
# The .odb file is a ZIP containing 'database/script' (HSQLDB data)
TEMP_DIR=$(mktemp -d)
unzip -q "$ODB_PATH" "database/script" -d "$TEMP_DIR"

SCRIPT_PATH="$TEMP_DIR/database/script"

# Use Python to parse the HSQLDB script and verify data
# We do this here to avoid needing to install heavy dependencies or replicate DB logic in verifier.py
# The script parses the INSERT statements directly.

python3 -c "
import sys
import re
import json

script_path = '$SCRIPT_PATH'
playlist_name_target = 'Epic Rock'
genre_target = 'Rock'
min_duration = 300000

# Data stores
genres = {} # id -> name
tracks = {} # id -> {genre_id, milliseconds, composer_is_not_null}
playlists = {} # id -> name
playlist_tracks = [] # list of (playlist_id, track_id)

try:
    with open(script_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('INSERT INTO'):
                continue
            
            # Basic SQL parsing - handling standard HSQLDB exports
            # Format: INSERT INTO \"Table\" VALUES(val1, val2, ...)
            
            # Extract Table Name
            m_table = re.match(r'INSERT INTO \"([^\"]+)\"', line)
            if not m_table:
                continue
            table = m_table.group(1)
            
            # Extract Values part
            # This is a simplification. Real SQL parsing handles nested parens/quotes.
            # But HSQLDB script dump format is very regular.
            val_part = line[line.find('VALUES(') + 7 : -1]
            
            # Split by comma respecting quotes is hard with regex alone.
            # We'll use a simple state machine parser for CSV-like structure
            values = []
            current_val = []
            in_quote = False
            for char in val_part:
                if char == '\'' and not in_quote:
                    in_quote = True
                elif char == '\'' and in_quote:
                    # check for escape (double quote) - rare in this specific dump but possible
                    pass 
                    # Actually HSQLDB escapes ' as '' inside strings.
                    # We just toggle for now, simplistic.
                    in_quote = False # This might be buggy if '' exists
                elif char == ',' and not in_quote:
                    values.append(''.join(current_val).strip())
                    current_val = []
                    continue
                current_val.append(char)
            values.append(''.join(current_val).strip())
            
            # Clean up values (remove surrounding quotes for strings)
            clean_values = []
            for v in values:
                if v.startswith('\'') and v.endswith('\''):
                    clean_values.append(v[1:-1])
                else:
                    clean_values.append(v)
            
            values = clean_values

            if table == 'Genre':
                # Schema: GenreId, Name
                if len(values) >= 2:
                    genres[values[0]] = values[1]
            
            elif table == 'Track':
                # Schema: TrackId, Name, AlbumId, MediaTypeId, GenreId, Composer, Milliseconds, Bytes, UnitPrice
                # We need indices: 0(Id), 4(GenreId), 5(Composer), 6(Ms)
                if len(values) >= 7:
                    tid = values[0]
                    gid = values[4]
                    composer = values[5]
                    ms = values[6]
                    
                    try:
                        tracks[tid] = {
                            'genre_id': gid,
                            'ms': int(ms),
                            'has_composer': (composer != 'NULL' and composer != '')
                        }
                    except ValueError:
                        pass

            elif table == 'Playlist':
                # Schema: PlaylistId, Name
                if len(values) >= 2:
                    playlists[values[0]] = values[1]

            elif table == 'PlaylistTrack':
                # Schema: PlaylistId, TrackId
                if len(values) >= 2:
                    playlist_tracks.append((values[0], values[1]))

    # --- Analysis ---
    
    # 1. Find Target Genre ID
    rock_genre_id = None
    for gid, name in genres.items():
        if name == genre_target:
            rock_genre_id = gid
            break
            
    # 2. Determine Ground Truth Track IDs
    ground_truth_ids = set()
    if rock_genre_id:
        for tid, tdata in tracks.items():
            if (tdata['genre_id'] == rock_genre_id and 
                tdata['ms'] > min_duration and 
                tdata['has_composer']):
                ground_truth_ids.add(tid)
    
    # 3. Find Agent's New Playlist
    agent_playlist_id = None
    agent_playlist_name = None
    
    # Looking for 'Epic Rock', checking case-insensitive to be kind
    for pid, name in playlists.items():
        if name.lower() == playlist_name_target.lower():
            agent_playlist_id = pid
            agent_playlist_name = name
            break
            
    # 4. Get Agent's Selected Tracks
    agent_track_ids = set()
    if agent_playlist_id:
        for pid, tid in playlist_tracks:
            if pid == agent_playlist_id:
                agent_track_ids.add(tid)
                
    # 5. Calculate Metrics
    tp = len(agent_track_ids.intersection(ground_truth_ids))
    fp = len(agent_track_ids - ground_truth_ids)
    fn = len(ground_truth_ids - agent_track_ids)
    
    result = {
        'playlist_found': bool(agent_playlist_id),
        'playlist_name': agent_playlist_name,
        'playlist_id': agent_playlist_id,
        'rock_genre_id': rock_genre_id,
        'ground_truth_count': len(ground_truth_ids),
        'agent_count': len(agent_track_ids),
        'true_positives': tp,
        'false_positives': fp,
        'false_negatives': fn,
        'ground_truth_ids': list(ground_truth_ids),
        'agent_ids': list(agent_track_ids)
    }
    
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_DIR/analysis.json"

# Combine into final result
ANALYSIS_CONTENT=$(cat "$TEMP_DIR/analysis.json")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "analysis": $ANALYSIS_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -rf "$TEMP_DIR" "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="