#!/bin/bash
# export_result.sh - Post-task hook for fred_labor_market_analysis

echo "=== Exporting FRED Labor Market Analysis Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Stop Firefox to flush databases (WAL files)
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# 3. Read Task Start Time
TASK_START=$(cat /tmp/task_start_timestamp.txt 2>/dev/null || echo "0")
TASK_START_US=$((TASK_START * 1000000))

# 4. Locate Files
CSV_PATH="/home/ga/Documents/labor_market_data.csv"
IMG_PATH="/home/ga/Documents/labor_market_chart.png"

# Check CSV
CSV_EXISTS="false"
CSV_SIZE=0
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH")
    # Copy to /tmp for easy extraction by verifier
    cp "$CSV_PATH" /tmp/exported_data.csv
fi

# Check Image
IMG_EXISTS="false"
IMG_SIZE=0
if [ -f "$IMG_PATH" ]; then
    IMG_EXISTS="true"
    IMG_SIZE=$(stat -c %s "$IMG_PATH")
fi

# 5. Check Firefox History & Bookmarks
PROFILE_DIR=$(cat /tmp/firefox_profile_path.txt 2>/dev/null || echo "")
PLACES_DB="$PROFILE_DIR/places.sqlite"

FRED_VISITS=0
BOOKMARK_FOUND="false"
BOOKMARK_TITLE=""

if [ -f "$PLACES_DB" ]; then
    # Checkpoint WAL to ensure data is in main DB
    sqlite3 "$PLACES_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    
    # Copy to temp to avoid locks
    cp "$PLACES_DB" /tmp/places_export.sqlite
    
    # Check Visits to fred.stlouisfed.org
    FRED_VISITS=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT COUNT(*) FROM moz_historyvisits h JOIN moz_places p ON h.place_id=p.id \
         WHERE p.url LIKE '%fred.stlouisfed.org%' AND h.visit_date > $TASK_START_US;" 2>/dev/null || echo "0")
         
    # Check for Bookmark
    # Look for bookmark title containing "Labor Market" created recently (timestamp check hard in SQL, just check existence)
    BM_ROW=$(sqlite3 /tmp/places_export.sqlite \
        "SELECT title FROM moz_bookmarks \
         WHERE type=1 AND title LIKE '%Labor Market Dashboard%' LIMIT 1;" 2>/dev/null || echo "")
    
    if [ -n "$BM_ROW" ]; then
        BOOKMARK_FOUND="true"
        BOOKMARK_TITLE="$BM_ROW"
    fi
    
    rm -f /tmp/places_export.sqlite
fi

# 6. Create JSON Result
cat > /tmp/task_result.json <<EOF
{
  "task_start_time": $TASK_START,
  "csv_exists": $CSV_EXISTS,
  "csv_size": $CSV_SIZE,
  "csv_path": "/tmp/exported_data.csv",
  "img_exists": $IMG_EXISTS,
  "img_size": $IMG_SIZE,
  "fred_visits": $FRED_VISITS,
  "bookmark_found": $BOOKMARK_FOUND,
  "bookmark_title": "$BOOKMARK_TITLE"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/exported_data.csv 2>/dev/null || true

echo "Export complete. Result JSON:"
cat /tmp/task_result.json