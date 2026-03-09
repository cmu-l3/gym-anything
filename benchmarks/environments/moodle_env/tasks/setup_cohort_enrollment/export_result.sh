#!/bin/bash
# Export script for Setup Cohort Enrollment task

echo "=== Exporting Cohort Enrollment Result ==="

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

# ------------------------------------------------------------------
# Retrieve course IDs (from setup baselines or live query)
# ------------------------------------------------------------------
CS110_ID=$(cat /tmp/cs110_course_id 2>/dev/null | tr -d '[:space:]')
if [ -z "$CS110_ID" ]; then
    CS110_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CS110'" | tr -d '[:space:]')
fi
CS110_ID=${CS110_ID:-0}

ENG110_ID=$(cat /tmp/eng110_course_id 2>/dev/null | tr -d '[:space:]')
if [ -z "$ENG110_ID" ]; then
    ENG110_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='ENG110'" | tr -d '[:space:]')
fi
ENG110_ID=${ENG110_ID:-0}

echo "CS110 id=$CS110_ID, ENG110 id=$ENG110_ID"

# ------------------------------------------------------------------
# Find the target cohort
# ------------------------------------------------------------------
COHORT_FOUND="false"
COHORT_ID=""
COHORT_NAME=""
COHORT_IDNUMBER=""

COHORT_DATA=$(moodle_query "SELECT id, name, idnumber FROM mdl_cohort WHERE idnumber='eng2024' OR LOWER(name) LIKE '%engineering%cohort%2024%' ORDER BY id DESC LIMIT 1")

if [ -n "$COHORT_DATA" ]; then
    COHORT_FOUND="true"
    COHORT_ID=$(echo "$COHORT_DATA"      | cut -f1 | tr -d '[:space:]')
    COHORT_NAME=$(echo "$COHORT_DATA"    | cut -f2)
    COHORT_IDNUMBER=$(echo "$COHORT_DATA"| cut -f3)
    echo "Cohort found: id=$COHORT_ID, name='$COHORT_NAME', idnumber='$COHORT_IDNUMBER'"
else
    echo "Cohort 'eng2024' / 'Engineering Program Cohort 2024' NOT found"
fi

# ------------------------------------------------------------------
# Cohort member count
# ------------------------------------------------------------------
COHORT_MEMBER_COUNT="0"
if [ -n "$COHORT_ID" ] && [ "$COHORT_ID" != "0" ]; then
    COHORT_MEMBER_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_cohort_members WHERE cohortid=${COHORT_ID}" | tr -d '[:space:]')
    COHORT_MEMBER_COUNT=${COHORT_MEMBER_COUNT:-0}
    echo "Cohort member count: $COHORT_MEMBER_COUNT"
fi

# ------------------------------------------------------------------
# Check whether each specific user is in the cohort
# ------------------------------------------------------------------
SAFE_COHORT_ID="${COHORT_ID:-0}"

ALICE_IN=$(moodle_query "SELECT COUNT(*) FROM mdl_cohort_members WHERE cohortid=${SAFE_COHORT_ID} AND userid=(SELECT id FROM mdl_user WHERE username='eng_alice' AND deleted=0 LIMIT 1)" | tr -d '[:space:]')
ALICE_IN=${ALICE_IN:-0}

BOB_IN=$(moodle_query "SELECT COUNT(*) FROM mdl_cohort_members WHERE cohortid=${SAFE_COHORT_ID} AND userid=(SELECT id FROM mdl_user WHERE username='eng_bob' AND deleted=0 LIMIT 1)" | tr -d '[:space:]')
BOB_IN=${BOB_IN:-0}

CAROL_IN=$(moodle_query "SELECT COUNT(*) FROM mdl_cohort_members WHERE cohortid=${SAFE_COHORT_ID} AND userid=(SELECT id FROM mdl_user WHERE username='eng_carol' AND deleted=0 LIMIT 1)" | tr -d '[:space:]')
CAROL_IN=${CAROL_IN:-0}

DAVE_IN=$(moodle_query "SELECT COUNT(*) FROM mdl_cohort_members WHERE cohortid=${SAFE_COHORT_ID} AND userid=(SELECT id FROM mdl_user WHERE username='eng_dave' AND deleted=0 LIMIT 1)" | tr -d '[:space:]')
DAVE_IN=${DAVE_IN:-0}

EMMA_IN=$(moodle_query "SELECT COUNT(*) FROM mdl_cohort_members WHERE cohortid=${SAFE_COHORT_ID} AND userid=(SELECT id FROM mdl_user WHERE username='eng_emma' AND deleted=0 LIMIT 1)" | tr -d '[:space:]')
EMMA_IN=${EMMA_IN:-0}

echo "Members in cohort: alice=$ALICE_IN, bob=$BOB_IN, carol=$CAROL_IN, dave=$DAVE_IN, emma=$EMMA_IN"

# ------------------------------------------------------------------
# Cohort sync enrollment method configured for CS110
# ------------------------------------------------------------------
CS110_COHORT_SYNC="0"
if [ "$CS110_ID" != "0" ] && [ "$SAFE_COHORT_ID" != "0" ]; then
    CS110_COHORT_SYNC=$(moodle_query "SELECT COUNT(*) FROM mdl_enrol WHERE enrol='cohort' AND courseid=${CS110_ID} AND customint1=${SAFE_COHORT_ID}" | tr -d '[:space:]')
    CS110_COHORT_SYNC=${CS110_COHORT_SYNC:-0}
fi
echo "CS110 cohort sync enrollment configured: $CS110_COHORT_SYNC"

# ------------------------------------------------------------------
# Cohort sync enrollment method configured for ENG110
# ------------------------------------------------------------------
ENG110_COHORT_SYNC="0"
if [ "$ENG110_ID" != "0" ] && [ "$SAFE_COHORT_ID" != "0" ]; then
    ENG110_COHORT_SYNC=$(moodle_query "SELECT COUNT(*) FROM mdl_enrol WHERE enrol='cohort' AND courseid=${ENG110_ID} AND customint1=${SAFE_COHORT_ID}" | tr -d '[:space:]')
    ENG110_COHORT_SYNC=${ENG110_COHORT_SYNC:-0}
fi
echo "ENG110 cohort sync enrollment configured: $ENG110_COHORT_SYNC"

# ------------------------------------------------------------------
# Count how many of the 5 cohort users are actively enrolled in CS110
# (regardless of enrollment method, to allow for manual-enrollment fallback)
# ------------------------------------------------------------------
CS110_ENROLLED_COUNT="0"
if [ "$CS110_ID" != "0" ] && [ "$SAFE_COHORT_ID" != "0" ]; then
    CS110_ENROLLED_COUNT=$(moodle_query "SELECT COUNT(DISTINCT ue.userid) FROM mdl_user_enrolments ue JOIN mdl_enrol e ON ue.enrolid=e.id WHERE e.courseid=${CS110_ID} AND ue.status=0 AND ue.userid IN (SELECT userid FROM mdl_cohort_members WHERE cohortid=${SAFE_COHORT_ID})" | tr -d '[:space:]')
    CS110_ENROLLED_COUNT=${CS110_ENROLLED_COUNT:-0}
fi
echo "CS110: $CS110_ENROLLED_COUNT of 5 cohort members enrolled"

# ------------------------------------------------------------------
# Count how many of the 5 cohort users are actively enrolled in ENG110
# ------------------------------------------------------------------
ENG110_ENROLLED_COUNT="0"
if [ "$ENG110_ID" != "0" ] && [ "$SAFE_COHORT_ID" != "0" ]; then
    ENG110_ENROLLED_COUNT=$(moodle_query "SELECT COUNT(DISTINCT ue.userid) FROM mdl_user_enrolments ue JOIN mdl_enrol e ON ue.enrolid=e.id WHERE e.courseid=${ENG110_ID} AND ue.status=0 AND ue.userid IN (SELECT userid FROM mdl_cohort_members WHERE cohortid=${SAFE_COHORT_ID})" | tr -d '[:space:]')
    ENG110_ENROLLED_COUNT=${ENG110_ENROLLED_COUNT:-0}
fi
echo "ENG110: $ENG110_ENROLLED_COUNT of 5 cohort members enrolled"

# ------------------------------------------------------------------
# Baseline cohort count from setup
# ------------------------------------------------------------------
INITIAL_COHORT_COUNT=$(cat /tmp/initial_cohort_count 2>/dev/null | tr -d '[:space:]')
INITIAL_COHORT_COUNT=${INITIAL_COHORT_COUNT:-0}

CURRENT_COHORT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_cohort" | tr -d '[:space:]')
CURRENT_COHORT_COUNT=${CURRENT_COHORT_COUNT:-0}

echo "Cohort count: initial=$INITIAL_COHORT_COUNT, current=$CURRENT_COHORT_COUNT"

# ------------------------------------------------------------------
# JSON escape helper
# ------------------------------------------------------------------
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    echo "$s"
}

COHORT_NAME_ESC=$(json_escape "$COHORT_NAME")
COHORT_IDNUMBER_ESC=$(json_escape "$COHORT_IDNUMBER")

# ------------------------------------------------------------------
# Write result JSON
# ------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/cohort_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "cs110_course_id": ${CS110_ID:-0},
    "eng110_course_id": ${ENG110_ID:-0},
    "initial_cohort_count": ${INITIAL_COHORT_COUNT:-0},
    "current_cohort_count": ${CURRENT_COHORT_COUNT:-0},
    "cohort_found": $COHORT_FOUND,
    "cohort_id": "${COHORT_ID:-}",
    "cohort_name": "${COHORT_NAME_ESC}",
    "cohort_idnumber": "${COHORT_IDNUMBER_ESC}",
    "cohort_member_count": ${COHORT_MEMBER_COUNT:-0},
    "alice_in_cohort": ${ALICE_IN:-0},
    "bob_in_cohort": ${BOB_IN:-0},
    "carol_in_cohort": ${CAROL_IN:-0},
    "dave_in_cohort": ${DAVE_IN:-0},
    "emma_in_cohort": ${EMMA_IN:-0},
    "cs110_cohort_sync_configured": ${CS110_COHORT_SYNC:-0},
    "eng110_cohort_sync_configured": ${ENG110_COHORT_SYNC:-0},
    "cs110_cohort_enrolled_count": ${CS110_ENROLLED_COUNT:-0},
    "eng110_cohort_enrolled_count": ${ENG110_ENROLLED_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/setup_cohort_enrollment_result.json

echo ""
cat /tmp/setup_cohort_enrollment_result.json
echo ""
echo "=== Export Complete ==="
