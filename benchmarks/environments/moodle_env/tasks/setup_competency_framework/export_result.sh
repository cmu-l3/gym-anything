#!/bin/bash
# Export script for Setup Competency Framework task

echo "=== Exporting Competency Framework Result ==="

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

# Retrieve PSY301 course ID (from setup baseline or live query)
COURSE_ID=$(cat /tmp/psy301_course_id 2>/dev/null | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='PSY301'" | tr -d '[:space:]')
fi
COURSE_ID=${COURSE_ID:-0}
echo "PSY301 Course ID: $COURSE_ID"

# Retrieve initial framework count baseline
INITIAL_FRAMEWORK_COUNT=$(cat /tmp/psy301_initial_framework_count 2>/dev/null | tr -d '[:space:]')
INITIAL_FRAMEWORK_COUNT=${INITIAL_FRAMEWORK_COUNT:-0}

# Current total framework count
CURRENT_FRAMEWORK_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency_framework" 2>/dev/null | tr -d '[:space:]')
CURRENT_FRAMEWORK_COUNT=${CURRENT_FRAMEWORK_COUNT:-0}
echo "Framework count: initial=$INITIAL_FRAMEWORK_COUNT, current=$CURRENT_FRAMEWORK_COUNT"

# --- Framework check: look for edu-psych-comp or similar ---
FRAMEWORK_FOUND="false"
FRAMEWORK_ID=""
FRAMEWORK_SHORTNAME=""
FRAMEWORK_FULLNAME=""

FRAMEWORK_DATA=$(moodle_query "SELECT id, shortname, fullname FROM mdl_competency_framework WHERE LOWER(shortname) = 'edu-psych-comp' OR LOWER(shortname) LIKE '%edu%psych%' ORDER BY id DESC LIMIT 1" 2>/dev/null)

if [ -n "$FRAMEWORK_DATA" ]; then
    FRAMEWORK_FOUND="true"
    FRAMEWORK_ID=$(echo "$FRAMEWORK_DATA" | cut -f1 | tr -d '[:space:]')
    FRAMEWORK_SHORTNAME=$(echo "$FRAMEWORK_DATA" | cut -f2)
    FRAMEWORK_FULLNAME=$(echo "$FRAMEWORK_DATA" | cut -f3)
    echo "Framework found: id=$FRAMEWORK_ID, shortname='$FRAMEWORK_SHORTNAME', fullname='$FRAMEWORK_FULLNAME'"
else
    echo "Framework 'edu-psych-comp' NOT found"
fi

# --- Competency counts within the framework ---
COMPETENCY_COUNT="0"
LEARNING_THEORIES_EXISTS="false"
DEV_PSYCH_EXISTS="false"
ASSESSMENT_EXISTS="false"

if [ -n "$FRAMEWORK_ID" ] && [ "$FRAMEWORK_ID" != "0" ]; then
    COMPETENCY_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency WHERE competencyframeworkid=$FRAMEWORK_ID" 2>/dev/null | tr -d '[:space:]')
    COMPETENCY_COUNT=${COMPETENCY_COUNT:-0}
    echo "Competency count in framework: $COMPETENCY_COUNT"

    # Check for "Learning Theories and Applications"
    LT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency WHERE competencyframeworkid=$FRAMEWORK_ID AND (LOWER(shortname) LIKE '%learning%theor%' OR LOWER(description) LIKE '%learning%theor%')" 2>/dev/null | tr -d '[:space:]')
    [ "${LT_COUNT:-0}" -gt 0 ] 2>/dev/null && LEARNING_THEORIES_EXISTS="true"

    # Check for "Developmental Psychology"
    DP_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency WHERE competencyframeworkid=$FRAMEWORK_ID AND (LOWER(shortname) LIKE '%develop%' OR LOWER(shortname) LIKE '%develop%psych%')" 2>/dev/null | tr -d '[:space:]')
    [ "${DP_COUNT:-0}" -gt 0 ] 2>/dev/null && DEV_PSYCH_EXISTS="true"

    # Check for "Educational Assessment and Measurement"
    AM_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency WHERE competencyframeworkid=$FRAMEWORK_ID AND (LOWER(shortname) LIKE '%assessment%' OR LOWER(shortname) LIKE '%measurement%')" 2>/dev/null | tr -d '[:space:]')
    [ "${AM_COUNT:-0}" -gt 0 ] 2>/dev/null && ASSESSMENT_EXISTS="true"

    echo "Competency checks: learning_theories=$LEARNING_THEORIES_EXISTS, dev_psych=$DEV_PSYCH_EXISTS, assessment=$ASSESSMENT_EXISTS"
else
    echo "Skipping competency checks - no framework found"
fi

# --- Course-competency links for PSY301 ---
COURSE_COMP_COUNT="0"
if [ "$COURSE_ID" != "0" ]; then
    COURSE_COMP_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency_coursecomp WHERE courseid=$COURSE_ID" 2>/dev/null | tr -d '[:space:]')
    COURSE_COMP_COUNT=${COURSE_COMP_COUNT:-0}
    echo "Course-competency links for PSY301: $COURSE_COMP_COUNT"
fi

# --- Activity-competency links ---
ACTIVITY_COMP_COUNT="0"
ESSAY_COMP_LINKED="false"
ASSESSMENT_COMP_LINKED="false"
ESSAY_CMID=""
ASSESSMENT_CMID=""

if [ "$COURSE_ID" != "0" ]; then
    # Total activity-competency links in PSY301
    ACTIVITY_COMP_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency_modulecomp WHERE cmid IN (SELECT id FROM mdl_course_modules WHERE course=$COURSE_ID)" 2>/dev/null | tr -d '[:space:]')
    ACTIVITY_COMP_COUNT=${ACTIVITY_COMP_COUNT:-0}
    echo "Total activity-competency links in PSY301: $ACTIVITY_COMP_COUNT"

    # Find cmid for "Learning Theories Essay"
    ESSAY_CMID=$(moodle_query "SELECT cm.id FROM mdl_course_modules cm JOIN mdl_assign a ON cm.instance=a.id JOIN mdl_modules m ON cm.module=m.id WHERE a.course=$COURSE_ID AND LOWER(a.name) LIKE '%learning%theor%essay%' AND m.name='assign' LIMIT 1" 2>/dev/null | tr -d '[:space:]')
    echo "Learning Theories Essay cmid: ${ESSAY_CMID:-not found}"

    if [ -n "$ESSAY_CMID" ] && [ "$ESSAY_CMID" != "0" ]; then
        ESSAY_COMP_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency_modulecomp WHERE cmid=$ESSAY_CMID" 2>/dev/null | tr -d '[:space:]')
        [ "${ESSAY_COMP_COUNT:-0}" -gt 0 ] 2>/dev/null && ESSAY_COMP_LINKED="true"
    fi
    echo "Learning Theories Essay has competency linked: $ESSAY_COMP_LINKED"

    # Find cmid for "Assessment Design Project"
    ASSESSMENT_CMID=$(moodle_query "SELECT cm.id FROM mdl_course_modules cm JOIN mdl_assign a ON cm.instance=a.id JOIN mdl_modules m ON cm.module=m.id WHERE a.course=$COURSE_ID AND LOWER(a.name) LIKE '%assessment%design%' AND m.name='assign' LIMIT 1" 2>/dev/null | tr -d '[:space:]')
    echo "Assessment Design Project cmid: ${ASSESSMENT_CMID:-not found}"

    if [ -n "$ASSESSMENT_CMID" ] && [ "$ASSESSMENT_CMID" != "0" ]; then
        ASSESSMENT_COMP_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency_modulecomp WHERE cmid=$ASSESSMENT_CMID" 2>/dev/null | tr -d '[:space:]')
        [ "${ASSESSMENT_COMP_COUNT:-0}" -gt 0 ] 2>/dev/null && ASSESSMENT_COMP_LINKED="true"
    fi
    echo "Assessment Design Project has competency linked: $ASSESSMENT_COMP_LINKED"
fi

# Escape strings for JSON
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    echo "$s"
}

FRAMEWORK_SHORTNAME_ESC=$(json_escape "$FRAMEWORK_SHORTNAME")
FRAMEWORK_FULLNAME_ESC=$(json_escape "$FRAMEWORK_FULLNAME")

# Write result JSON
TEMP_JSON=$(mktemp /tmp/competency_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_framework_count": ${INITIAL_FRAMEWORK_COUNT:-0},
    "current_framework_count": ${CURRENT_FRAMEWORK_COUNT:-0},
    "framework_found": $FRAMEWORK_FOUND,
    "framework_id": "${FRAMEWORK_ID:-}",
    "framework_shortname": "${FRAMEWORK_SHORTNAME_ESC}",
    "framework_fullname": "${FRAMEWORK_FULLNAME_ESC}",
    "competency_count": ${COMPETENCY_COUNT:-0},
    "learning_theories_exists": $LEARNING_THEORIES_EXISTS,
    "dev_psych_exists": $DEV_PSYCH_EXISTS,
    "assessment_exists": $ASSESSMENT_EXISTS,
    "course_comp_count": ${COURSE_COMP_COUNT:-0},
    "activity_comp_count": ${ACTIVITY_COMP_COUNT:-0},
    "essay_cmid": "${ESSAY_CMID:-}",
    "essay_comp_linked": $ESSAY_COMP_LINKED,
    "assessment_cmid": "${ASSESSMENT_CMID:-}",
    "assessment_comp_linked": $ASSESSMENT_COMP_LINKED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/setup_competency_framework_result.json

echo ""
cat /tmp/setup_competency_framework_result.json
echo ""
echo "=== Export Complete ==="
