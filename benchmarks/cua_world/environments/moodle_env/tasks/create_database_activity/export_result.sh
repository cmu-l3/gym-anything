#!/bin/bash
# Export script for Create Database Activity task

echo "=== Exporting Create Database Activity Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"; echo "Result saved to $dest_path"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve stored course ID and baseline
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_data_count 2>/dev/null || echo "0")

# 1. Get current count
CURRENT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_data WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_COUNT=${CURRENT_COUNT:-0}

# 2. Find the target activity
# Search by name (case-insensitive)
ACTIVITY_DATA=$(moodle_query "SELECT id, name, intro FROM mdl_data WHERE course=$COURSE_ID AND LOWER(name) LIKE '%medication reference%' ORDER BY id DESC LIMIT 1")

ACTIVITY_FOUND="false"
ACTIVITY_ID=""
ACTIVITY_NAME=""
FIELDS_JSON="[]"
ENTRIES_JSON="[]"

if [ -n "$ACTIVITY_DATA" ]; then
    ACTIVITY_FOUND="true"
    ACTIVITY_ID=$(echo "$ACTIVITY_DATA" | cut -f1 | tr -d '[:space:]')
    ACTIVITY_NAME=$(echo "$ACTIVITY_DATA" | cut -f2)
    
    # 3. Get Field Definitions
    # mdl_data_fields: id, dataid, type, name, description, param1 (options), param2, etc.
    # Note: param1 for 'menu' contains newline-separated options
    
    # We construct a JSON array of fields manually via iteration
    FIELDS_RAW=$(moodle_query "SELECT id, type, name, param1 FROM mdl_data_fields WHERE dataid=$ACTIVITY_ID")
    
    FIELDS_JSON="["
    FIRST_FIELD=true
    
    # Read line by line. IFS set to newline to handle spaces in names
    IFS=$'\n'
    for line in $FIELDS_RAW; do
        if [ "$FIRST_FIELD" = true ]; then
            FIRST_FIELD=false
        else
            FIELDS_JSON="$FIELDS_JSON,"
        fi
        
        FID=$(echo "$line" | cut -f1)
        FTYPE=$(echo "$line" | cut -f2)
        FNAME=$(echo "$line" | cut -f3)
        # Param1 might contain newlines in the DB, but mysql client usually escapes them or prints strictly tab-separated
        # For menu options, we might get just one line or encoded chars. 
        # We'll just grab it as is.
        FPARAM=$(echo "$line" | cut -f4)
        
        # Escape for JSON
        FNAME_ESC=$(echo "$FNAME" | sed 's/"/\\"/g')
        FPARAM_ESC=$(echo "$FPARAM" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
        
        FIELDS_JSON="$FIELDS_JSON {\"id\": \"$FID\", \"type\": \"$FTYPE\", \"name\": \"$FNAME_ESC\", \"param1\": \"$FPARAM_ESC\"}"
    done
    FIELDS_JSON="$FIELDS_JSON]"
    IFS=$' \t\n' # Reset IFS

    # 4. Get Entries (Records)
    # mdl_data_records: id, dataid
    # We want to sample the content of the latest record
    LATEST_RECORD_ID=$(moodle_query "SELECT id FROM mdl_data_records WHERE dataid=$ACTIVITY_ID ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
    
    if [ -n "$LATEST_RECORD_ID" ]; then
        # Get content for this record
        # mdl_data_content: fieldid, recordid, content
        CONTENT_RAW=$(moodle_query "SELECT f.name, c.content FROM mdl_data_content c JOIN mdl_data_fields f ON c.fieldid = f.id WHERE c.recordid=$LATEST_RECORD_ID")
        
        ENTRIES_JSON="[{"
        FIRST_ITEM=true
        
        IFS=$'\n'
        for line in $CONTENT_RAW; do
             if [ "$FIRST_ITEM" = true ]; then
                FIRST_ITEM=false
            else
                ENTRIES_JSON="$ENTRIES_JSON,"
            fi
            
            CNAME=$(echo "$line" | cut -f1)
            CCONTENT=$(echo "$line" | cut -f2)
            
            CNAME_ESC=$(echo "$CNAME" | sed 's/"/\\"/g')
            CCONTENT_ESC=$(echo "$CCONTENT" | sed 's/"/\\"/g')
            
            ENTRIES_JSON="$ENTRIES_JSON \"$CNAME_ESC\": \"$CCONTENT_ESC\""
        done
        ENTRIES_JSON="$ENTRIES_JSON}]"
        IFS=$' \t\n'
    else
        ENTRIES_JSON="[]"
    fi
fi

# Escape Activity Name
ACTIVITY_NAME_ESC=$(echo "$ACTIVITY_NAME" | sed 's/"/\\"/g')

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/db_task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "activity_found": $ACTIVITY_FOUND,
    "activity_name": "$ACTIVITY_NAME_ESC",
    "fields": $FIELDS_JSON,
    "entries": $ENTRIES_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_database_activity_result.json

echo ""
echo "Exported JSON:"
cat /tmp/create_database_activity_result.json
echo ""
echo "=== Export Complete ==="