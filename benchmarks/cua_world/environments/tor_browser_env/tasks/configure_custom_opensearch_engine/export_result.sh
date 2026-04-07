#!/bin/bash
# export_result.sh for configure_custom_opensearch_engine task

echo "=== Exporting configure_custom_opensearch_engine results ==="

TASK_NAME="configure_custom_opensearch_engine"
TASK_START_TS=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Find Tor Browser profile
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        echo "Using Tor Browser profile: $PROFILE_DIR"
        break
    fi
done

# Copy databases and files to /tmp to avoid active file locks
if [ -n "$PROFILE_DIR" ]; then
    cp "$PROFILE_DIR/search.json.mozlz4" "/tmp/search.json.mozlz4" 2>/dev/null || true
    cp "$PROFILE_DIR/places.sqlite" "/tmp/places_export.sqlite" 2>/dev/null || true
    cp "$PROFILE_DIR/places.sqlite-wal" "/tmp/places_export.sqlite-wal" 2>/dev/null || true
    cp "$PROFILE_DIR/places.sqlite-shm" "/tmp/places_export.sqlite-shm" 2>/dev/null || true
fi

# Run Python script to parse Mozilla LZ4 search config and query SQLite history
python3 << PYEOF > /tmp/${TASK_NAME}_result.json
import json
import os
import sqlite3

result = {
    "task_start_ts": $TASK_START_TS,
    "pypi_visited": False,
    "pypi_added_to_engines": False,
    "google_removed_or_hidden": False,
    "search_executed": False,
    "search_timestamp_valid": False,
    "search_url_found": ""
}

# 1. Parse search.json.mozlz4
search_config_path = "/tmp/search.json.mozlz4"
if os.path.exists(search_config_path):
    try:
        import lz4.block
        with open(search_config_path, "rb") as f:
            magic = f.read(8)
            if magic == b"mozLz40\0":
                compressed_data = f.read()
                json_data = lz4.block.decompress(compressed_data)
                config = json.loads(json_data)
                
                engines = config.get("engines", [])
                
                # Check if PyPI is added
                for engine in engines:
                    name = engine.get("_name", "").lower()
                    if "pypi" in name:
                        result["pypi_added_to_engines"] = True
                
                # Check if Google is removed (missing or hidden)
                google_found = False
                google_hidden = False
                for engine in engines:
                    if engine.get("_name", "").lower() == "google":
                        google_found = True
                        meta = engine.get("_meta", {})
                        if meta.get("hidden", False):
                            google_hidden = True
                
                if not google_found or google_hidden:
                    result["google_removed_or_hidden"] = True

    except Exception as e:
        result["search_parse_error"] = str(e)
else:
    result["google_removed_or_hidden"] = True # If missing, technically Google isn't there

# 2. Query places.sqlite for visits and search execution
places_db_path = "/tmp/places_export.sqlite"
if os.path.exists(places_db_path):
    try:
        conn = sqlite3.connect(places_db_path)
        conn.row_factory = sqlite3.Row
        c = conn.cursor()

        # Check for PyPI visit
        c.execute("""
            SELECT p.url FROM moz_places p 
            JOIN moz_historyvisits h ON p.id = h.place_id 
            WHERE p.url LIKE 'https://pypi.org/%'
            LIMIT 1
        """)
        if c.fetchone():
            result["pypi_visited"] = True

        # Check for address bar search execution
        # PyPI OpenSearch usually formats as https://pypi.org/search/?q=stem
        c.execute("""
            SELECT p.url, MAX(h.visit_date) as last_visit
            FROM moz_places p
            JOIN moz_historyvisits h ON p.id = h.place_id
            WHERE p.url LIKE 'https://pypi.org/search/?q=stem%'
            GROUP BY p.id
        """)
        row = c.fetchone()
        if row:
            result["search_executed"] = True
            result["search_url_found"] = row["url"]
            
            # Firefox stores visit_date in microseconds since Unix epoch
            visit_ts = int(row["last_visit"]) // 1000000
            if visit_ts > result["task_start_ts"]:
                result["search_timestamp_valid"] = True

        conn.close()
    except Exception as e:
        result["db_query_error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# Cleanup temporary files
rm -f /tmp/search.json.mozlz4 /tmp/places_export.sqlite* 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json