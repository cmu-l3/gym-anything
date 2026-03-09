#!/bin/bash
echo "=== Exporting Reconstruct Playlist Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot before closing
take_screenshot /tmp/task_final.png

# 2. Check if LibreOffice was running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# 3. Gracefully close LibreOffice to ensure data is flushed to ODB file
# HSQLDB in Base writes changes to the .odb file (specifically database/script) on save/close.
echo "Closing LibreOffice to flush changes..."
pkill -f "soffice" 2>/dev/null || true
# Wait for process to exit and file to write
sleep 5

# 4. Check file modification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_PATH="/home/ga/chinook.odb"
ODB_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    ODB_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 5. Extract and Analyze Database State
# Since we can't easily run a SQL query against the ODB file from bash without LO running in headless mode (which is flaky),
# we will unzip the ODB and parse the HSQLDB script file directly using Python.
# This is reliable because HSQLDB 1.8 stores the entire database state in 'database/script'.

echo "Extracting database script for analysis..."
WORK_DIR=$(mktemp -d)
unzip -q "$ODB_PATH" -d "$WORK_DIR" 2>/dev/null || echo "Failed to unzip ODB"

SCRIPT_FILE="$WORK_DIR/database/script"
ANALYSIS_JSON="/tmp/db_analysis.json"

if [ -f "$SCRIPT_FILE" ]; then
    echo "Parsing HSQLDB script..."
    python3 -c "
import re
import json
import sys

script_path = '$SCRIPT_FILE'
playlist_name = 'Heavy Classics'
target_tracks = [
    'Ace Of Spades', 
    'Master Of Puppets', 
    'For Whom The Bell Tolls', 
    'The Number Of The Beast', 
    'Run To The Hills'
]

results = {
    'playlist_found': False,
    'playlist_id': None,
    'linked_track_ids': [],
    'linked_track_names': [],
    'found_tracks_count': 0,
    'correct_tracks_count': 0,
    'extra_tracks_count': 0,
    'error': None
}

try:
    with open(script_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()

    # 1. Load Track Map (ID -> Name) and find Playlist ID
    track_map = {}
    playlist_id = None
    
    # HSQLDB INSERT format: INSERT INTO \"Table\" VALUES(ID,'String',...)
    # Regex is approximate but sufficient for standard Base HSQLDB output
    
    for line in lines:
        if not line.startswith('INSERT INTO'):
            continue
            
        # Parse Tracks
        if '\"Track\"' in line:
            # simple parse assuming ID is first, Name is second
            # INSERT INTO \"Track\" VALUES(1,'For Those About To Rock (We Salute You)',...)
            try:
                parts = line.split('VALUES(')[1]
                t_id = parts.split(',')[0].strip()
                # Name might contain commas, so be careful. 
                # Usually: 1,'Name',...
                # Split by comma, look at second element, strip quotes
                rest = parts.split(',', 1)[1]
                # Extract string literal
                if rest.startswith(\"'\"):
                    t_name = rest.split(\"','\")[0][1:] # crude extraction
                else:
                    t_name = \"unknown\"
                
                # Better approach: find ID and verify specific target names
                # Let's just map ID to the raw line part to check later if needed, 
                # or use a smarter split for our specific targets.
                
                # Actually, let's just search for our target tracks to get their IDs first?
                # No, we need to verify what the agent linked.
                pass
            except:
                pass

        # Parse Playlist
        if '\"Playlist\"' in line and playlist_name in line:
            # INSERT INTO \"Playlist\" VALUES(19,'Heavy Classics')
            try:
                parts = line.split('VALUES(')[1]
                p_id = parts.split(',')[0].strip()
                results['playlist_found'] = True
                results['playlist_id'] = p_id
            except:
                pass

    # Re-scan for Tracks with proper ID mapping now that we know we need them
    # We'll use a more robust regex for the specific lines we care about
    
    # Map all Track IDs to Names
    track_id_to_name = {}
    for line in lines:
        if 'INSERT INTO \"Track\"' in line:
            # match: INSERT INTO "Track" VALUES(1,'Name',...
            m = re.search(r'VALUES\s*\(\s*(\d+)\s*,\s*\'(.*?)\'', line)
            if m:
                track_id_to_name[m.group(1)] = m.group(2)

    # 2. Find links in PlaylistTrack for our Playlist ID
    if results['playlist_found'] and results['playlist_id']:
        pid = results['playlist_id']
        for line in lines:
            if 'INSERT INTO \"PlaylistTrack\"' in line:
                # INSERT INTO "PlaylistTrack" VALUES(1,3402) -> (PlaylistId, TrackId)
                # Note: HSQLDB order might vary, but usually it's defined in CREATE TABLE
                # CREATE TABLE \"PlaylistTrack\"(\"PlaylistId\" INTEGER NOT NULL,\"TrackId\" INTEGER NOT NULL...
                if f'VALUES({pid},' in line or f'VALUES({pid} ,' in line:
                    # Extract Track ID
                    # Regex for VALUES(pid, tid)
                    m = re.search(r'VALUES\s*\(\s*' + re.escape(pid) + r'\s*,\s*(\d+)', line)
                    if m:
                        tid = m.group(1)
                        results['linked_track_ids'].append(tid)
                        tname = track_id_to_name.get(tid, 'Unknown Track ID ' + tid)
                        results['linked_track_names'].append(tname)

    # 3. Analyze results
    for name in results['linked_track_names']:
        # Case insensitive match
        found = False
        for target in target_tracks:
            if target.lower() == name.lower():
                results['correct_tracks_count'] += 1
                found = True
                break
        if not found:
            results['extra_tracks_count'] += 1
            
    results['found_tracks_count'] = len(results['linked_track_names'])

except Exception as e:
    results['error'] = str(e)

print(json.dumps(results))
" > "$ANALYSIS_JSON"
else
    echo "ERROR: Could not find database/script in ODB file"
    echo '{"error": "ODB extraction failed"}' > "$ANALYSIS_JSON"
fi

# 6. Create Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
ANALYSIS_CONTENT=$(cat "$ANALYSIS_JSON")

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "odb_modified": $ODB_MODIFIED,
    "odb_size": $ODB_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "db_analysis": $ANALYSIS_CONTENT
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -rf "$WORK_DIR" "$TEMP_JSON" "$ANALYSIS_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="