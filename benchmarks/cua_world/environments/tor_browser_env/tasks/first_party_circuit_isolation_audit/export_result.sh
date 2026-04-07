#!/bin/bash
# export_result.sh for first_party_circuit_isolation_audit
# Exports DB history and checks for the agent's output file

echo "=== Exporting first_party_circuit_isolation_audit results ==="

TASK_NAME="first_party_circuit_isolation_audit"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
CLEARNET_IP=$(cat /tmp/clearnet_ip.txt 2>/dev/null || echo "unknown")

# 1. Check agent's output file metadata
OUTPUT_FILE="/home/ga/Documents/isolation_audit.json"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

# 2. Extract History from places.sqlite to verify they actually browsed
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/${TASK_NAME}_places.sqlite"

# Copy database to avoid WAL locks
if [ -n "$PROFILE_DIR" ] && [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
fi

# Check history for the three domains
python3 << 'PYEOF' > /tmp/${TASK_NAME}_db_result.json
import sqlite3
import json
import os

db_path = "/tmp/first_party_circuit_isolation_audit_places.sqlite"
domains_to_check = ["api.ipify.org", "icanhazip.com", "checkip.amazonaws.com"]

result = {
    "db_found": False,
    "visited_domains": []
}

if not os.path.exists(db_path):
    print(json.dumps(result))
    exit()

result["db_found"] = True
visited = set()

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    c.execute("""
        SELECT p.url
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
    """)
    urls = [row["url"].lower() for row in c.fetchall()]

    for url in urls:
        for domain in domains_to_check:
            if domain in url:
                visited.add(domain)

    conn.close()
    result["visited_domains"] = list(visited)
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Merge into final result
python3 << PYEOF2
import json

try:
    with open('/tmp/${TASK_NAME}_db_result.json', 'r') as f:
        db = json.load(f)
except:
    db = {"db_found": False, "visited_domains": []}

db.update({
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "clearnet_ip": "$CLEARNET_IP",
    "task_start": $TASK_START
})

with open('/tmp/task_result.json', 'w') as f:
    json.dump(db, f, indent=2)
PYEOF2

chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_DB" "${TEMP_DB}-wal" "${TEMP_DB}-shm" /tmp/${TASK_NAME}_db_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json