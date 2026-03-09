#!/bin/bash
# Shared utilities for all OrientDB tasks

ORIENTDB_ROOT_PASS="GymAnything123!"
ORIENTDB_URL="http://localhost:2480"
ORIENTDB_AUTH="root:${ORIENTDB_ROOT_PASS}"

# ---- OrientDB REST helpers ----

# Execute SQL command against a database, return raw JSON
orientdb_sql() {
    local db="$1"
    local sql="$2"
    curl -s -X POST \
        -u "${ORIENTDB_AUTH}" \
        -H "Content-Type: application/json" \
        -d "{\"command\":\"${sql}\"}" \
        "${ORIENTDB_URL}/command/${db}/sql" 2>/dev/null
}

# Execute a SELECT query (GET endpoint) and return JSON
orientdb_query() {
    local db="$1"
    local sql="$2"
    local encoded
    encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''${sql}'''))")
    curl -s -u "${ORIENTDB_AUTH}" \
        "${ORIENTDB_URL}/query/${db}/sql/${encoded}/100" 2>/dev/null
}

# Check if a class exists in a database (returns 0=yes, 1=no)
orientdb_class_exists() {
    local db="$1"
    local class_name="$2"
    local result
    result=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/${db}" 2>/dev/null)
    echo "$result" | python3 -c "
import json, sys
data = json.load(sys.stdin)
classes = [c.get('name','') for c in data.get('classes', [])]
sys.exit(0 if '${class_name}' in classes else 1)
" 2>/dev/null
}

# Check if an index exists in a database (returns 0=yes, 1=no)
orientdb_index_exists() {
    local db="$1"
    local index_name="$2"
    local result
    result=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/${db}" 2>/dev/null)
    echo "$result" | python3 -c "
import json, sys
data = json.load(sys.stdin)
indexes = [idx.get('name','') for cls in data.get('classes', []) for idx in cls.get('indexes', [])]
sys.exit(0 if '${index_name}' in indexes else 1)
" 2>/dev/null
}

# Check if a database exists (returns 0=yes, 1=no)
orientdb_db_exists() {
    local db="$1"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "${ORIENTDB_AUTH}" \
        "${ORIENTDB_URL}/database/${db}" 2>/dev/null)
    [ "$code" = "200" ]
}

# Wait for OrientDB API to be ready
wait_for_orientdb() {
    local timeout="${1:-120}"
    local elapsed=0
    echo "Waiting for OrientDB..."
    while [ $elapsed -lt $timeout ]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" -u "${ORIENTDB_AUTH}" \
            "${ORIENTDB_URL}/listDatabases" 2>/dev/null || echo "000")
        if [ "$code" = "200" ]; then
            echo "OrientDB is ready"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "ERROR: OrientDB not ready after ${timeout}s"
    return 1
}

# ---- Firefox helpers ----

# Kill Firefox cleanly (handles snap Firefox lock files)
kill_firefox() {
    pkill -TERM -f firefox 2>/dev/null || true
    sleep 2
    pkill -9 -f firefox 2>/dev/null || true
    sleep 3
    # Remove all profile lock files (snap Firefox uses .parentlock and lock)
    find /home/ga/.mozilla -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/.mozilla -name "lock" -delete 2>/dev/null || true
    # Also remove recovery files that can trigger "already running" dialog
    find /home/ga/.mozilla -name "recovery*.jsonlz4" -delete 2>/dev/null || true
    find /home/ga/.mozilla -name "previous.jsonlz4" -delete 2>/dev/null || true
    sleep 1
    # Confirm no Firefox processes remain
    if pgrep -f firefox > /dev/null 2>&1; then
        sleep 3
        pkill -9 -f firefox 2>/dev/null || true
        sleep 2
    fi
}

# Launch Firefox to a specific URL and wait for it to open
launch_firefox() {
    local url="$1"
    local wait_sec="${2:-8}"
    kill_firefox
    su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile '${url}' &"
    sleep "${wait_sec}"
}

# Ensure Firefox is open at the OrientDB Studio home page
ensure_firefox_at_studio() {
    local url="${1:-http://localhost:2480/studio/index.html}"
    # Check if Firefox is running
    if ! pgrep -f firefox > /dev/null 2>&1; then
        echo "Firefox not running, launching..."
        launch_firefox "$url"
    else
        # Navigate to URL
        su - ga -c "DISPLAY=:1 xdotool search --onlyvisible --name 'Mozilla Firefox' windowactivate --sync" 2>/dev/null || true
        sleep 1
    fi
}

# Take a screenshot and save to path
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

echo "task_utils.sh loaded"
