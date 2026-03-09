#!/bin/bash
echo "=== Exporting Batch Delete Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Find the database file
DB_FILE=$(find /home/ga -name "*.mdb" 2>/dev/null | grep -i "lobby" | head -1)
if [ -z "$DB_FILE" ]; then
    # Fallback search in wine prefix
    DB_FILE=$(find /home/ga/.wine/drive_c -name "*.mdb" 2>/dev/null | grep -i "lobby" | head -1)
fi

DB_FOUND="false"
APEX_COUNT=0
SUMMIT_COUNT=0
DB_MODIFIED="false"

if [ -n "$DB_FILE" ] && [ -f "$DB_FILE" ]; then
    DB_FOUND="true"
    
    # Check modification time
    DB_MTIME=$(stat -c %Y "$DB_FILE")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    
    # Extract data using mdb-tools
    if command -v mdb-export >/dev/null; then
        TABLES=$(mdb-tables "$DB_FILE")
        # Try to find the main visitor table
        VISITOR_TABLE=$(echo "$TABLES" | tr ' ' '\n' | grep -i "Visitor" | head -1)
        
        if [ -n "$VISITOR_TABLE" ]; then
            # Export to CSV for counting
            mdb-export "$DB_FILE" "$VISITOR_TABLE" > /tmp/final_db_export.csv
            
            # Count records (case insensitive)
            APEX_COUNT=$(grep -i "Apex Contractors" /tmp/final_db_export.csv | wc -l)
            SUMMIT_COUNT=$(grep -i "Summit Partners" /tmp/final_db_export.csv | wc -l)
        fi
    fi
fi

# Get initial counts
INIT_APEX=$(cat /tmp/init_apex_count.txt 2>/dev/null || echo "2")
INIT_SUMMIT=$(cat /tmp/init_summit_count.txt 2>/dev/null || echo "2")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_found": $DB_FOUND,
    "db_path": "$DB_FILE",
    "db_modified": $DB_MODIFIED,
    "final_apex_count": $APEX_COUNT,
    "final_summit_count": $SUMMIT_COUNT,
    "initial_apex_count": $INIT_APEX,
    "initial_summit_count": $INIT_SUMMIT,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="