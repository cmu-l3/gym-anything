#!/bin/bash
# Export script for Create Glossary with Entries task

echo "=== Exporting Glossary Task Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type moodle_query &>/dev/null; then
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
    moodle_query_headers() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
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

# Get BIO101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get baseline
INITIAL_GLOSSARY_COUNT=$(cat /tmp/initial_glossary_count 2>/dev/null || echo "0")

# Get current glossary count
CURRENT_GLOSSARY_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_glossary WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_GLOSSARY_COUNT=${CURRENT_GLOSSARY_COUNT:-0}

echo "Glossary count: initial=$INITIAL_GLOSSARY_COUNT, current=$CURRENT_GLOSSARY_COUNT"

# Look for the target glossary (fuzzy match on 'Medical Terminology')
# We select the most recently created one matching the name
GLOSSARY_DATA=$(moodle_query "SELECT id, name, defaultapproval, allowduplicatedentries, timemodified FROM mdl_glossary WHERE course=$COURSE_ID AND LOWER(name) LIKE '%medical terminology%' ORDER BY id DESC LIMIT 1")

GLOSSARY_FOUND="false"
GLOSSARY_ID=""
GLOSSARY_NAME=""
DEFAULT_APPROVAL="0"
ALLOW_DUPLICATES="0"
TIME_MODIFIED="0"
ENTRIES_JSON="[]"

if [ -n "$GLOSSARY_DATA" ]; then
    GLOSSARY_FOUND="true"
    GLOSSARY_ID=$(echo "$GLOSSARY_DATA" | cut -f1 | tr -d '[:space:]')
    GLOSSARY_NAME=$(echo "$GLOSSARY_DATA" | cut -f2)
    DEFAULT_APPROVAL=$(echo "$GLOSSARY_DATA" | cut -f3 | tr -d '[:space:]')
    ALLOW_DUPLICATES=$(echo "$GLOSSARY_DATA" | cut -f4 | tr -d '[:space:]')
    TIME_MODIFIED=$(echo "$GLOSSARY_DATA" | cut -f5 | tr -d '[:space:]')

    echo "Glossary found: ID=$GLOSSARY_ID, Name='$GLOSSARY_NAME'"
    echo "Settings: Approval=$DEFAULT_APPROVAL, Duplicates=$ALLOW_DUPLICATES"

    # Fetch entries for this glossary
    # We construct a JSON array of entries manually to avoid complex parsing dependencies
    # Select concept and definition. Use hex export to handle special chars safely if possible, 
    # but here we'll use standard select and escape quotes.
    
    echo "Fetching entries..."
    # Query: id, concept, definition (truncated for log), timecreated
    moodle_query_headers "SELECT id, concept, LEFT(definition, 50) as def_start FROM mdl_glossary_entries WHERE glossaryid=$GLOSSARY_ID"

    # Construct JSON for entries using a loop
    # Note: This is fragile with special characters, so we try to be careful
    ENTRIES_RAW=$(moodle_query "SELECT concept, definition, timecreated FROM mdl_glossary_entries WHERE glossaryid=$GLOSSARY_ID")
    
    # Python script to safely parse the tab-separated raw entries and output JSON
    ENTRIES_JSON=$(python3 -c "
import sys
import json

entries = []
try:
    # Read raw tab-separated lines from stdin
    # moodle_query outputs tab-separated values
    # We need to handle potentially multi-line definitions which mysql might output with escaped newlines
    # But moodle_query uses -N -B which outputs TSV. Newlines in fields are usually escaped as \n
    
    raw_data = sys.stdin.read()
    if raw_data.strip():
        for line in raw_data.strip().split('\n'):
            parts = line.split('\t')
            if len(parts) >= 3:
                entries.append({
                    'concept': parts[0],
                    'definition': parts[1],
                    'timecreated': int(parts[2]) if parts[2].isdigit() else 0
                })
except Exception as e:
    sys.stderr.write(str(e))

print(json.dumps(entries))
" <<< "$ENTRIES_RAW")

else
    echo "Target glossary NOT found in BIO101"
fi

# Escape glossary name for JSON inclusion
GLOSSARY_NAME_ESC=$(echo "$GLOSSARY_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/glossary_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": ${TASK_START_TIME:-0},
    "course_id": ${COURSE_ID:-0},
    "initial_glossary_count": ${INITIAL_GLOSSARY_COUNT:-0},
    "current_glossary_count": ${CURRENT_GLOSSARY_COUNT:-0},
    "glossary_found": $GLOSSARY_FOUND,
    "glossary_id": "$GLOSSARY_ID",
    "glossary_name": "$GLOSSARY_NAME_ESC",
    "default_approval": ${DEFAULT_APPROVAL:-0},
    "allow_duplicates": ${ALLOW_DUPLICATES:-0},
    "timemodified": ${TIME_MODIFIED:-0},
    "entries": $ENTRIES_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_glossary_result.json

echo ""
cat /tmp/create_glossary_result.json
echo ""
echo "=== Export Complete ==="