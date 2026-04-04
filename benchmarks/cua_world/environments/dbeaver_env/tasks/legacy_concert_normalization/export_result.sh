#!/bin/bash
echo "=== Exporting Legacy Concert Normalization Result ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/concert_bookings.db"
GT_PATH="/tmp/concert_ground_truth.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if DB file exists
DB_EXISTS="false"
DB_SIZE=0
DB_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    DB_SIZE=$(stat -c%s "$DB_PATH")
    DB_MTIME=$(stat -c%Y "$DB_PATH")
    
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_CREATED_DURING_TASK="true"
    fi
fi

# Initialize schema info
TABLES_FOUND="[]"
VENUES_COUNT=0
ARTISTS_COUNT=0
CONCERTS_COUNT=0
STAGING_TABLE_EXISTS="false"
SCHEMA_VALID="false"
DATA_INTEGRITY_SCORE=0
VENUES_COLUMNS="[]"
ARTISTS_COLUMNS="[]"
CONCERTS_COLUMNS="[]"

if [ "$DB_EXISTS" = "true" ]; then
    # Get list of tables
    TABLES_JSON=$(sqlite3 "$DB_PATH" "SELECT json_group_array(name) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';" 2>/dev/null || echo "[]")
    
    # Check for staging table artifacts
    if echo "$TABLES_JSON" | grep -qi "raw\|import\|csv\|temp"; then
        STAGING_TABLE_EXISTS="true"
    fi

    # Get row counts
    VENUES_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM Venues;" 2>/dev/null || echo 0)
    ARTISTS_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM Artists;" 2>/dev/null || echo 0)
    CONCERTS_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM Concerts;" 2>/dev/null || echo 0)

    # Get column info
    VENUES_COLUMNS=$(sqlite3 "$DB_PATH" "SELECT json_group_array(name) FROM pragma_table_info('Venues');" 2>/dev/null || echo "[]")
    ARTISTS_COLUMNS=$(sqlite3 "$DB_PATH" "SELECT json_group_array(name) FROM pragma_table_info('Artists');" 2>/dev/null || echo "[]")
    CONCERTS_COLUMNS=$(sqlite3 "$DB_PATH" "SELECT json_group_array(name) FROM pragma_table_info('Concerts');" 2>/dev/null || echo "[]")

    # Data Integrity Check: Reconstruct the flat data via SQL and count matches
    # This query attempts to reconstruct the original CSV view
    # We verify the count of rows that have valid joins
    RECONSTRUCTED_COUNT=$(sqlite3 "$DB_PATH" "
        SELECT COUNT(*) 
        FROM Concerts c
        JOIN Venues v ON c.VenueId = v.VenueId OR c.VenueId = v.id  -- handle varied PK naming
        JOIN Artists a ON c.ArtistId = a.ArtistId OR c.ArtistId = a.id;" 2>/dev/null || echo 0)
fi

# Check DBeaver connection config
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
CONNECTION_CREATED="false"
CONNECTION_NAME_MATCH="false"

if [ -f "$DBEAVER_CONFIG" ]; then
    CONN_INFO=$(python3 -c "
import json
try:
    with open('$DBEAVER_CONFIG') as f:
        data = json.load(f)
    found = False
    name_match = False
    for k, v in data.get('connections', {}).items():
        if 'concert_bookings.db' in v.get('configuration', {}).get('database', ''):
            found = True
        if 'ConcertBookings' == v.get('name', ''):
            name_match = True
    print(f'{found}|{name_match}')
except:
    print('False|False')
")
    CONNECTION_CREATED=$(echo "$CONN_INFO" | cut -d'|' -f1)
    CONNECTION_NAME_MATCH=$(echo "$CONN_INFO" | cut -d'|' -f2)
fi

# Ground Truth Loading
GT_TOTAL_ROWS=$(python3 -c "import json; print(json.load(open('$GT_PATH')).get('total_rows', 0))" 2>/dev/null || echo 0)
GT_DISTINCT_VENUES=$(python3 -c "import json; print(json.load(open('$GT_PATH')).get('distinct_venues', 0))" 2>/dev/null || echo 0)
GT_DISTINCT_ARTISTS=$(python3 -c "import json; print(json.load(open('$GT_PATH')).get('distinct_artists', 0))" 2>/dev/null || echo 0)

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "db_exists": $DB_EXISTS,
    "db_size": $DB_SIZE,
    "db_created_during_task": $DB_CREATED_DURING_TASK,
    "tables_found": $TABLES_JSON,
    "staging_table_exists": $STAGING_TABLE_EXISTS,
    "venues_count": $VENUES_COUNT,
    "artists_count": $ARTISTS_COUNT,
    "concerts_count": $CONCERTS_COUNT,
    "reconstructed_count": ${RECONSTRUCTED_COUNT:-0},
    "venues_columns": $VENUES_COLUMNS,
    "artists_columns": $ARTISTS_COLUMNS,
    "concerts_columns": $CONCERTS_COLUMNS,
    "connection_created": $(echo $CONNECTION_CREATED | tr '[:upper:]' '[:lower:]'),
    "connection_name_match": $(echo $CONNECTION_NAME_MATCH | tr '[:upper:]' '[:lower:]'),
    "gt_total_rows": $GT_TOTAL_ROWS,
    "gt_distinct_venues": $GT_DISTINCT_VENUES,
    "gt_distinct_artists": $GT_DISTINCT_ARTISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Secure copy
cp /tmp/task_result.json /tmp/final_result.json
chmod 666 /tmp/final_result.json

echo "Export complete. Result:"
cat /tmp/final_result.json