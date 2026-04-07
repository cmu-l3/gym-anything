#!/bin/bash
# Export script for Configure Course Requests task

echo "=== Exporting Result ==="

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

# Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

# --- LOAD REFERENCE DATA (From setup) ---
REF_SCIENCE_ID=$(cat /tmp/ref_science_cat_id 2>/dev/null || echo "0")
REF_TEACHER_ID=$(cat /tmp/ref_teacher_id 2>/dev/null || echo "0")
INITIAL_ENABLED=$(cat /tmp/initial_enabled_state 2>/dev/null || echo "0")
INITIAL_REQUEST_COUNT=$(cat /tmp/initial_request_count 2>/dev/null || echo "0")

# --- CHECK CONFIGURATION (Part 1: Admin) ---
# Check 'enablecourserequests'
CONFIG_ENABLED=$(moodle_query "SELECT value FROM mdl_config WHERE name='enablecourserequests'" | tr -d '[:space:]')
CONFIG_ENABLED=${CONFIG_ENABLED:-0}

# Check 'defaultrequestcategory'
CONFIG_DEFAULT_CAT=$(moodle_query "SELECT value FROM mdl_config WHERE name='defaultrequestcategory'" | tr -d '[:space:]')
CONFIG_DEFAULT_CAT=${CONFIG_DEFAULT_CAT:-0}

echo "Config: Enabled=$CONFIG_ENABLED (Initial=$INITIAL_ENABLED), DefaultCat=$CONFIG_DEFAULT_CAT (Ref=$REF_SCIENCE_ID)"

# --- CHECK COURSE REQUEST (Part 2: Teacher) ---
# Look for the specific request "Advanced Quantum Mechanics"
REQUEST_DATA=$(moodle_query "SELECT id, fullname, shortname, category, requester, timecreated FROM mdl_course_request WHERE fullname='Advanced Quantum Mechanics' ORDER BY id DESC LIMIT 1")

REQ_FOUND="false"
REQ_ID=""
REQ_FULLNAME=""
REQ_SHORTNAME=""
REQ_CAT=""
REQ_USER=""
REQ_TIME=""

if [ -n "$REQUEST_DATA" ]; then
    REQ_FOUND="true"
    REQ_ID=$(echo "$REQUEST_DATA" | cut -f1 | tr -d '[:space:]')
    REQ_FULLNAME=$(echo "$REQUEST_DATA" | cut -f2)
    REQ_SHORTNAME=$(echo "$REQUEST_DATA" | cut -f3)
    REQ_CAT=$(echo "$REQUEST_DATA" | cut -f4 | tr -d '[:space:]')
    REQ_USER=$(echo "$REQUEST_DATA" | cut -f5 | tr -d '[:space:]')
    REQ_TIME=$(echo "$REQUEST_DATA" | cut -f6 | tr -d '[:space:]')
    echo "Request found: ID=$REQ_ID, Name='$REQ_FULLNAME', User=$REQ_USER, Cat=$REQ_CAT"
else
    echo "Request for 'Advanced Quantum Mechanics' NOT found"
fi

# Get current total count
CURRENT_REQUEST_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_course_request" | tr -d '[:space:]')

# --- EXPORT JSON ---
TEMP_JSON=$(mktemp /tmp/course_request_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "ref_science_id": ${REF_SCIENCE_ID:-0},
    "ref_teacher_id": ${REF_TEACHER_ID:-0},
    "initial_enabled": ${INITIAL_ENABLED:-0},
    "current_enabled": ${CONFIG_ENABLED:-0},
    "current_default_cat": ${CONFIG_DEFAULT_CAT:-0},
    "request_found": $REQ_FOUND,
    "request": {
        "id": "${REQ_ID}",
        "fullname": "$(echo "$REQ_FULLNAME" | sed 's/"/\\"/g')",
        "shortname": "$(echo "$REQ_SHORTNAME" | sed 's/"/\\"/g')",
        "category_id": "${REQ_CAT}",
        "requester_id": "${REQ_USER}",
        "timecreated": "${REQ_TIME}"
    },
    "initial_count": ${INITIAL_REQUEST_COUNT:-0},
    "current_count": ${CURRENT_REQUEST_COUNT:-0},
    "export_timestamp": $(date +%s)
}
EOF

safe_write_json "$TEMP_JSON" /tmp/course_request_result.json

echo ""
cat /tmp/course_request_result.json
echo ""
echo "=== Export Complete ==="