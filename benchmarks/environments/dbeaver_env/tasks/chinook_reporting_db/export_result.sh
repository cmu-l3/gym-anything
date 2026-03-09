#!/bin/bash
# Export script for chinook_reporting_db task
# Inspects the created SQLite database and exports results

echo "=== Exporting Chinook Reporting DB Result ==="

source /workspace/scripts/task_utils.sh

REPORT_DB="/home/ga/Documents/databases/chinook_reports.db"
SCRIPT_FILE="/home/ga/Documents/scripts/create_reports_db.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if Report DB exists
DB_EXISTS="false"
DB_SIZE=0
if [ -f "$REPORT_DB" ]; then
    DB_EXISTS="true"
    DB_SIZE=$(stat -c%s "$REPORT_DB" 2>/dev/null || echo 0)
fi

# 2. Check if DBeaver Connection exists
CONNECTION_FOUND="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Look for name "ChinookReports" in the config
    if grep -q "ChinookReports" "$DBEAVER_CONFIG"; then
        CONNECTION_FOUND="true"
    fi
fi

# 3. Inspect Database Content (if it exists)
TBL_ARTIST_EXISTS="false"
TBL_GENRE_EXISTS="false"
TBL_MONTHLY_EXISTS="false"

ARTIST_ROWS=0
GENRE_ROWS=0
MONTHLY_ROWS=0

ARTIST_COLS=""
GENRE_COLS=""
MONTHLY_COLS=""

VAL_IM_TRACKS=0
VAL_IM_ALBUMS=0
VAL_IM_DURATION=0
VAL_TOP_GENRE_NAME=""
VAL_TOP_GENRE_REV=0
VAL_TOTAL_REV=0

if [ "$DB_EXISTS" = "true" ]; then
    # Check Tables
    TABLES=$(sqlite3 "$REPORT_DB" ".tables" 2>/dev/null)
    
    if echo "$TABLES" | grep -q "artist_summary"; then 
        TBL_ARTIST_EXISTS="true"
        ARTIST_ROWS=$(sqlite3 "$REPORT_DB" "SELECT COUNT(*) FROM artist_summary;" 2>/dev/null || echo 0)
        ARTIST_COLS=$(sqlite3 "$REPORT_DB" "PRAGMA table_info(artist_summary);" 2>/dev/null | cut -d'|' -f2 | tr '\n' ',' | sed 's/,$//')
        
        # Spot check Iron Maiden (ArtistId 90 usually, checking by name is safer)
        IM_DATA=$(sqlite3 "$REPORT_DB" "SELECT AlbumCount, TrackCount, TotalDurationMinutes FROM artist_summary WHERE ArtistName = 'Iron Maiden' LIMIT 1;" 2>/dev/null)
        if [ -n "$IM_DATA" ]; then
            VAL_IM_ALBUMS=$(echo "$IM_DATA" | cut -d'|' -f1)
            VAL_IM_TRACKS=$(echo "$IM_DATA" | cut -d'|' -f2)
            VAL_IM_DURATION=$(echo "$IM_DATA" | cut -d'|' -f3)
        fi
    fi

    if echo "$TABLES" | grep -q "genre_revenue"; then 
        TBL_GENRE_EXISTS="true"
        GENRE_ROWS=$(sqlite3 "$REPORT_DB" "SELECT COUNT(*) FROM genre_revenue;" 2>/dev/null || echo 0)
        GENRE_COLS=$(sqlite3 "$REPORT_DB" "PRAGMA table_info(genre_revenue);" 2>/dev/null | cut -d'|' -f2 | tr '\n' ',' | sed 's/,$//')
        
        # Spot check Top Genre
        TOP_GENRE_DATA=$(sqlite3 "$REPORT_DB" "SELECT GenreName, TotalRevenue FROM genre_revenue ORDER BY TotalRevenue DESC LIMIT 1;" 2>/dev/null)
        if [ -n "$TOP_GENRE_DATA" ]; then
            VAL_TOP_GENRE_NAME=$(echo "$TOP_GENRE_DATA" | cut -d'|' -f1)
            VAL_TOP_GENRE_REV=$(echo "$TOP_GENRE_DATA" | cut -d'|' -f2)
        fi
    fi

    if echo "$TABLES" | grep -q "monthly_sales"; then 
        TBL_MONTHLY_EXISTS="true"
        MONTHLY_ROWS=$(sqlite3 "$REPORT_DB" "SELECT COUNT(*) FROM monthly_sales;" 2>/dev/null || echo 0)
        MONTHLY_COLS=$(sqlite3 "$REPORT_DB" "PRAGMA table_info(monthly_sales);" 2>/dev/null | cut -d'|' -f2 | tr '\n' ',' | sed 's/,$//')
        
        # Spot check Total Revenue (sum of months)
        VAL_TOTAL_REV=$(sqlite3 "$REPORT_DB" "SELECT SUM(TotalRevenue) FROM monthly_sales;" 2>/dev/null || echo 0)
    fi
fi

# 4. Check Script
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
fi

# 5. Load Ground Truth
GT_JSON="{}"
if [ -f /tmp/chinook_gt.json ]; then
    GT_JSON=$(cat /tmp/chinook_gt.json)
fi

# 6. Anti-gaming check
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo 0)
DB_MODIFIED_TIME=0
if [ -f "$REPORT_DB" ]; then
    DB_MODIFIED_TIME=$(stat -c%Y "$REPORT_DB" 2>/dev/null || echo 0)
fi
CREATED_DURING_TASK="false"
if [ "$DB_MODIFIED_TIME" -ge "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Construct Result JSON
cat > /tmp/task_result.json << EOF
{
    "db_exists": $DB_EXISTS,
    "db_created_during_task": $CREATED_DURING_TASK,
    "connection_found": $CONNECTION_FOUND,
    "script_exists": $SCRIPT_EXISTS,
    "tables": {
        "artist_summary": {
            "exists": $TBL_ARTIST_EXISTS,
            "rows": $ARTIST_ROWS,
            "columns": "$ARTIST_COLS",
            "im_albums": ${VAL_IM_ALBUMS:-0},
            "im_tracks": ${VAL_IM_TRACKS:-0},
            "im_duration": ${VAL_IM_DURATION:-0}
        },
        "genre_revenue": {
            "exists": $TBL_GENRE_EXISTS,
            "rows": $GENRE_ROWS,
            "columns": "$GENRE_COLS",
            "top_name": "$VAL_TOP_GENRE_NAME",
            "top_revenue": ${VAL_TOP_GENRE_REV:-0}
        },
        "monthly_sales": {
            "exists": $TBL_MONTHLY_EXISTS,
            "rows": $MONTHLY_ROWS,
            "columns": "$MONTHLY_COLS",
            "total_revenue": ${VAL_TOTAL_REV:-0}
        }
    },
    "ground_truth": $GT_JSON
}
EOF

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="