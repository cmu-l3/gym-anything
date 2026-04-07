#!/bin/bash
# Export script for Create Competency Framework task

echo "=== Exporting Competency Framework Result ==="

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

# 1. Take Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Baseline Values
INITIAL_FW_COUNT=$(cat /tmp/initial_fw_count 2>/dev/null || echo "0")
INITIAL_COMP_COUNT=$(cat /tmp/initial_comp_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Verify Framework (DLF001)
FW_DATA=$(moodle_query "SELECT id, shortname, idnumber, scaleid FROM mdl_competency_framework WHERE idnumber='DLF001'")
FW_FOUND="false"
FW_ID=""
FW_NAME=""
FW_SCALE_ID=""

if [ -n "$FW_DATA" ]; then
    FW_FOUND="true"
    FW_ID=$(echo "$FW_DATA" | cut -f1)
    FW_NAME=$(echo "$FW_DATA" | cut -f2)
    FW_IDNUMBER=$(echo "$FW_DATA" | cut -f3)
    FW_SCALE_ID=$(echo "$FW_DATA" | cut -f4)
    echo "Framework Found: ID=$FW_ID, Name=$FW_NAME"
fi

# 4. Verify Competencies (DL-IL, DL-DC, DL-DA)
COMP_IDS_FOUND=0
COMP_IL_FOUND="false"
COMP_DC_FOUND="false"
COMP_DA_FOUND="false"

# Use loops or individual checks. We need specific IDs.
# Check DL-IL
if [ -n "$(moodle_query "SELECT id FROM mdl_competency WHERE idnumber='DL-IL' AND competencyframeworkid='$FW_ID'")" ]; then
    COMP_IL_FOUND="true"
    ((COMP_IDS_FOUND++))
fi
# Check DL-DC
if [ -n "$(moodle_query "SELECT id FROM mdl_competency WHERE idnumber='DL-DC' AND competencyframeworkid='$FW_ID'")" ]; then
    COMP_DC_FOUND="true"
    ((COMP_IDS_FOUND++))
fi
# Check DL-DA
if [ -n "$(moodle_query "SELECT id FROM mdl_competency WHERE idnumber='DL-DA' AND competencyframeworkid='$FW_ID'")" ]; then
    COMP_DA_FOUND="true"
    ((COMP_IDS_FOUND++))
fi

echo "Competencies Found: $COMP_IDS_FOUND / 3"

# 5. Verify Links to Course (CS101)
# First get CS101 ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CS101'")
LINKED_COUNT=0

if [ -n "$COURSE_ID" ] && [ "$FW_FOUND" = "true" ]; then
    # Check links for each competency
    # We join competency table to ensure we are counting links for OUR competencies
    LINKED_COUNT=$(moodle_query "
        SELECT COUNT(*) 
        FROM mdl_competency_coursecomp cc
        JOIN mdl_competency c ON cc.competencyid = c.id
        WHERE cc.courseid = $COURSE_ID 
        AND c.competencyframeworkid = $FW_ID
        AND c.idnumber IN ('DL-IL', 'DL-DC', 'DL-DA')
    ")
fi

echo "Competencies Linked to CS101: $LINKED_COUNT"

# 6. Check Creation Time (Anti-Gaming)
# Verify framework was created after task start
FW_CREATED_DURING_TASK="false"
if [ "$FW_FOUND" = "true" ]; then
    FW_TIMECREATED=$(moodle_query "SELECT timecreated FROM mdl_competency_framework WHERE id=$FW_ID")
    if [ "$FW_TIMECREATED" -ge "$TASK_START" ]; then
        FW_CREATED_DURING_TASK="true"
    fi
fi

# 7. Create JSON Result
# Escape name for JSON
FW_NAME_ESC=$(echo "$FW_NAME" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/comp_framework_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_fw_count": ${INITIAL_FW_COUNT:-0},
    "framework_found": $FW_FOUND,
    "framework_name": "$FW_NAME_ESC",
    "framework_idnumber": "DLF001",
    "framework_scale_id": "${FW_SCALE_ID:-0}",
    "created_during_task": $FW_CREATED_DURING_TASK,
    "competencies_found_count": $COMP_IDS_FOUND,
    "competency_il_found": $COMP_IL_FOUND,
    "competency_dc_found": $COMP_DC_FOUND,
    "competency_da_found": $COMP_DA_FOUND,
    "links_to_course_count": ${LINKED_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_competency_framework_result.json

echo ""
cat /tmp/create_competency_framework_result.json
echo ""
echo "=== Export Complete ==="