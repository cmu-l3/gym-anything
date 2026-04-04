#!/bin/bash
echo "=== Exporting insert_new_artist_hierarchy results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Kill LibreOffice to ensure file locks are released and data is flushed to ODB
kill_libreoffice

# 2. Basic file verification
ODB_PATH="/home/ga/chinook.odb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"

if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Extract and parse database content
# HSQLDB embedded stores data in 'database/script' inside the ODB zip
echo "Extracting database script..."
rm -rf /tmp/odb_extract
mkdir -p /tmp/odb_extract
unzip -q "$ODB_PATH" "database/script" -d /tmp/odb_extract 2>/dev/null || echo "Unzip failed"

# 5. Parse the script file using Python to generate JSON result
# We need to find the inserted records and link them
python3 -c '
import sys
import json
import re

result = {
    "artist_found": False,
    "artist_id": None,
    "album_found": False,
    "album_id": None,
    "album_linked_correctly": False,
    "tracks_found": [],
    "tracks_linked_correctly": False,
    "data_integrity": True
}

try:
    with open("/tmp/odb_extract/database/script", "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    # HSQLDB INSERT format: INSERT INTO <table> VALUES(val1, val2, ...)
    
    # 1. Find Artist: INSERT INTO "Artist" VALUES(276,\u0027Dua Lipa\u0027)
    # Note: Strings are single-quoted.
    artist_pattern = r"INSERT INTO \"Artist\" VALUES\((\d+),.*Dua Lipa.*\)"
    artist_match = re.search(artist_pattern, content, re.IGNORECASE)
    
    if artist_match:
        result["artist_found"] = True
        result["artist_id"] = artist_match.group(1)
        print(f"Found Artist ID: {result[\"artist_id\"]}")

    # 2. Find Album: INSERT INTO "Album" VALUES(348,\u0027Future Nostalgia\u0027,276)
    if result["artist_id"]:
        # Look for Album with Title "Future Nostalgia" AND ArtistId
        # Format: AlbumId, Title, ArtistId
        album_pattern = r"INSERT INTO \"Album\" VALUES\((\d+),.*Future Nostalgia.*," + result["artist_id"] + r"\)"
        album_match = re.search(album_pattern, content, re.IGNORECASE)
        
        if album_match:
            result["album_found"] = True
            result["album_id"] = album_match.group(1)
            result["album_linked_correctly"] = True
            print(f"Found Album ID: {result[\"album_id\"]} linked to Artist")
        else:
            # Check if album exists but not linked correctly
            album_generic = re.search(r"INSERT INTO \"Album\" VALUES\((\d+),.*Future Nostalgia.*,(\d+)\)", content, re.IGNORECASE)
            if album_generic:
                result["album_found"] = True
                result["album_id"] = album_generic.group(1)
                print(f"Found Album ID: {result[\"album_id\"]} (Incorrect Link)")

    # 3. Find Tracks
    # Track columns: TrackId, Name, AlbumId, MediaTypeId, GenreId, Composer, Milliseconds, Bytes, UnitPrice
    target_tracks = ["Don''t Start Now", "Levitating", "Physical"] # Escaped single quote for regex if needed
    
    # Python regex for SQL values is tricky due to varying columns.
    # We simply look for the INSERT line containing the Track Name and the AlbumId
    
    for track_name in ["Don'\''t Start Now", "Levitating", "Physical"]:
        # Sanitize for regex: escape single quotes
        track_name_clean = track_name.replace("'\''", "'") # restore for display
        track_name_regex = track_name.replace("'\''", ".*") # loose match
        
        if result["album_id"]:
            # Check for track linked to album
            # We look for the name and the album ID in the same line
            # HSQLDB inserts usually put AlbumId as the 3rd value
            track_pattern = f"INSERT INTO \"Track\" VALUES\(.*{track_name_regex}.*,{result['album_id']},.*\)"
            if re.search(track_pattern, content, re.IGNORECASE):
                result["tracks_found"].append({"name": track_name_clean, "linked": True})
            else:
                # Check if track exists at all
                if re.search(f"INSERT INTO \"Track\" VALUES\(.*{track_name_regex}.*\)", content, re.IGNORECASE):
                     result["tracks_found"].append({"name": track_name_clean, "linked": False})
        else:
            # Album not found, just check existence
            if re.search(f"INSERT INTO \"Track\" VALUES\(.*{track_name_regex}.*\)", content, re.IGNORECASE):
                 result["tracks_found"].append({"name": track_name_clean, "linked": False})

    # Summary logic
    result["tracks_linked_correctly"] = all(t["linked"] for t in result["tracks_found"]) and len(result["tracks_found"]) == 3

except Exception as e:
    result["data_integrity"] = False
    result["error"] = str(e)
    print(f"Error parsing database: {e}")

# Save result
with open("/tmp/parsed_db_result.json", "w") as f:
    json.dump(result, f)
'

# 6. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_modified": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png",
    "db_parsing": $(cat /tmp/parsed_db_result.json 2>/dev/null || echo "{}")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="