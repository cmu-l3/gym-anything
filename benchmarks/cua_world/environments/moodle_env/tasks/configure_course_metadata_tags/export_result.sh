#!/bin/bash
# Export script for Configure Course Metadata Tags task

echo "=== Exporting Configure Course Metadata Tags Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if needed
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

# Load context
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null)
if [ -z "$COURSE_ID" ]; then
    # Fallback lookup
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
fi
echo "Checking course ID: $COURSE_ID"

# 1. Verify Custom Field Category "Catalog Info"
CATEGORY_ID=$(moodle_query "SELECT id FROM mdl_customfield_category WHERE LOWER(name)='catalog info' AND component='core_course' AND area='course' LIMIT 1" | tr -d '[:space:]')
CATEGORY_EXISTS="false"
if [ -n "$CATEGORY_ID" ]; then
    CATEGORY_EXISTS="true"
    echo "Found Category 'Catalog Info' (ID: $CATEGORY_ID)"
else
    echo "Category 'Catalog Info' NOT found"
fi

# 2. Verify Custom Field "Faculty"
FIELD_ID=$(moodle_query "SELECT id FROM mdl_customfield_field WHERE shortname='faculty' LIMIT 1" | tr -d '[:space:]')
FIELD_EXISTS="false"
FIELD_NAME=""
FIELD_TYPE=""
FIELD_CATEGORY_MATCH="false"

if [ -n "$FIELD_ID" ]; then
    FIELD_EXISTS="true"
    FIELD_INFO=$(moodle_query "SELECT name, type, categoryid FROM mdl_customfield_field WHERE id=$FIELD_ID")
    FIELD_NAME=$(echo "$FIELD_INFO" | cut -f1)
    FIELD_TYPE=$(echo "$FIELD_INFO" | cut -f2)
    ACTUAL_CAT_ID=$(echo "$FIELD_INFO" | cut -f3)
    
    if [ "$ACTUAL_CAT_ID" == "$CATEGORY_ID" ]; then
        FIELD_CATEGORY_MATCH="true"
    fi
    echo "Found Field 'Faculty' (ID: $FIELD_ID, Type: $FIELD_TYPE, In Correct Category: $FIELD_CATEGORY_MATCH)"
else
    echo "Field 'Faculty' NOT found"
fi

# 3. Verify Field Value on BIO101
FIELD_VALUE=""
FIELD_VALUE_MATCH="false"
if [ -n "$COURSE_ID" ] && [ -n "$FIELD_ID" ]; then
    FIELD_VALUE=$(moodle_query "SELECT value FROM mdl_customfield_data WHERE instanceid=$COURSE_ID AND fieldid=$FIELD_ID LIMIT 1")
    if [ "$FIELD_VALUE" == "Science" ]; then
        FIELD_VALUE_MATCH="true"
    fi
    echo "Field Value on BIO101: '$FIELD_VALUE'"
fi

# 4. Verify Tag "STEM" on BIO101
TAG_EXISTS="false"
TAG_LINKED="false"

# First find the tag ID (case-insensitive)
TAG_ID=$(moodle_query "SELECT id FROM mdl_tag WHERE LOWER(name)='stem' LIMIT 1" | tr -d '[:space:]')

if [ -n "$TAG_ID" ]; then
    TAG_EXISTS="true"
    # Check if linked to course
    LINK_CHECK=$(moodle_query "SELECT id FROM mdl_tag_instance WHERE tagid=$TAG_ID AND itemid=$COURSE_ID AND itemtype='course' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$LINK_CHECK" ]; then
        TAG_LINKED="true"
    fi
    echo "Tag 'STEM' found (ID: $TAG_ID). Linked to BIO101: $TAG_LINKED"
else
    echo "Tag 'STEM' NOT found in system"
fi

# 5. Check counts for anti-gaming
INITIAL_FIELD_COUNT=$(cat /tmp/initial_field_count 2>/dev/null || echo "0")
CURRENT_FIELD_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_customfield_field" | tr -d '[:space:]')

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/metadata_tags_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "category_exists": $CATEGORY_EXISTS,
    "field_exists": $FIELD_EXISTS,
    "field_name": "$FIELD_NAME",
    "field_type": "$FIELD_TYPE",
    "field_category_match": $FIELD_CATEGORY_MATCH,
    "field_value": "$FIELD_VALUE",
    "field_value_correct": $FIELD_VALUE_MATCH,
    "tag_exists": $TAG_EXISTS,
    "tag_linked": $TAG_LINKED,
    "initial_field_count": ${INITIAL_FIELD_COUNT:-0},
    "current_field_count": ${CURRENT_FIELD_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_course_metadata_tags_result.json

echo ""
cat /tmp/configure_course_metadata_tags_result.json
echo ""
echo "=== Export Complete ==="