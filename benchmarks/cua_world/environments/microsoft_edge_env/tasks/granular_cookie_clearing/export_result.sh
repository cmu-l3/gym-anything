#!/bin/bash
set -e
echo "=== Exporting Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to ensure SQLite DB is consistent/unlocked
echo "Stopping Edge to unlock database..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3

# 3. Locate Cookies DB
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"
COOKIES_DB=""
if [ -f "$PROFILE_DIR/Network/Cookies" ]; then
    COOKIES_DB="$PROFILE_DIR/Network/Cookies"
elif [ -f "$PROFILE_DIR/Cookies" ]; then
    COOKIES_DB="$PROFILE_DIR/Cookies"
fi

# 4. Analyze DB
GH_COUNT=0
SO_COUNT=0
GO_COUNT=0
DB_MTIME=0
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$COOKIES_DB" ]; then
    DB_MTIME=$(stat -c %Y "$COOKIES_DB")
    
    # Copy to temp to avoid any read locks
    cp "$COOKIES_DB" /tmp/cookies_final.sqlite
    
    GH_COUNT=$(sqlite3 /tmp/cookies_final.sqlite "SELECT count(*) FROM cookies WHERE host_key LIKE '%github.com%';" 2>/dev/null || echo "0")
    SO_COUNT=$(sqlite3 /tmp/cookies_final.sqlite "SELECT count(*) FROM cookies WHERE host_key LIKE '%stackoverflow.com%';" 2>/dev/null || echo "0")
    GO_COUNT=$(sqlite3 /tmp/cookies_final.sqlite "SELECT count(*) FROM cookies WHERE host_key LIKE '%google.com%';" 2>/dev/null || echo "0")
    
    rm -f /tmp/cookies_final.sqlite
else
    echo "Warning: Cookies DB not found."
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "db_mtime": $DB_MTIME,
    "github_cookies": $GH_COUNT,
    "stackoverflow_cookies": $SO_COUNT,
    "google_cookies": $GO_COUNT,
    "cookies_db_path": "$COOKIES_DB"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="