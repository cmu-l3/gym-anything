#!/bin/bash
echo "=== Exporting Event Cost Estimator Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Find the Survey
echo "Searching for survey..."
SURVEY_DATA=$(limesurvey_query "SELECT s.sid, s.active FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid=sl.surveyls_survey_id WHERE sl.surveyls_title LIKE '%Event Quote Calculator 2025%' LIMIT 1")

SID=""
ACTIVE="N"
FOUND="false"

if [ -n "$SURVEY_DATA" ]; then
    FOUND="true"
    SID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    ACTIVE=$(echo "$SURVEY_DATA" | awk '{print $2}')
    echo "Found Survey SID: $SID (Active: $ACTIVE)"
else
    echo "Survey not found by title. Checking newest survey..."
    # Fallback: check newest survey created after start time
    SID=$(limesurvey_query "SELECT sid FROM lime_surveys ORDER BY sid DESC LIMIT 1")
    if [ -n "$SID" ]; then
        TITLE=$(limesurvey_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID")
        ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SID")
        echo "Found newest survey SID: $SID, Title: $TITLE"
        # We will proceed with this SID for checking, but verifier might penalize wrong title
    fi
fi

# 2. Extract Question Data
GUESTS_Q_EXISTS="false"
GUESTS_Q_TYPE=""
PACKAGE_Q_EXISTS="false"
PACKAGE_Q_TYPE=""
TOTAL_COST_Q_EXISTS="false"
TOTAL_COST_Q_TYPE=""
TOTAL_COST_FORMULA=""
PACKAGE_ANSWER_CODES=""

if [ -n "$SID" ]; then
    # Get 'guests' question
    GUESTS_DATA=$(limesurvey_query "SELECT type FROM lime_questions WHERE sid=$SID AND title='guests' AND parent_qid=0 LIMIT 1")
    if [ -n "$GUESTS_DATA" ]; then
        GUESTS_Q_EXISTS="true"
        GUESTS_Q_TYPE="$GUESTS_DATA"
    fi

    # Get 'package' question
    PACKAGE_DATA=$(limesurvey_query "SELECT qid, type FROM lime_questions WHERE sid=$SID AND title='package' AND parent_qid=0 LIMIT 1")
    if [ -n "$PACKAGE_DATA" ]; then
        PACKAGE_Q_EXISTS="true"
        PACKAGE_QID=$(echo "$PACKAGE_DATA" | awk '{print $1}')
        PACKAGE_Q_TYPE=$(echo "$PACKAGE_DATA" | awk '{print $2}')
        
        # Get answer codes for 'package'
        # Group concat codes to check for 25, 55, 120
        CODES=$(limesurvey_query "SELECT GROUP_CONCAT(code ORDER BY code ASC SEPARATOR ',') FROM lime_answers WHERE qid=$PACKAGE_QID")
        PACKAGE_ANSWER_CODES="$CODES"
    fi

    # Get 'total_cost' question (Equation)
    # Note: Logic/Text is in lime_question_l10ns
    COST_DATA=$(limesurvey_query "SELECT q.qid, q.type, l.question 
        FROM lime_questions q 
        JOIN lime_question_l10ns l ON q.qid=l.qid 
        WHERE q.sid=$SID AND q.title='total_cost' AND q.parent_qid=0 LIMIT 1")
    
    if [ -n "$COST_DATA" ]; then
        TOTAL_COST_Q_EXISTS="true"
        # type is usually 2nd field, formula is the rest
        # We use cut/awk carefully
        TOTAL_COST_Q_TYPE=$(echo "$COST_DATA" | awk '{print $2}')
        
        # Extract formula text (might contain spaces)
        # Using python to fetch cleaner data or simple sed
        TOTAL_COST_FORMULA=$(limesurvey_query "SELECT question FROM lime_question_l10ns WHERE qid=$(echo "$COST_DATA" | awk '{print $1}')")
    fi
fi

# 3. Create JSON Result
# Sanitize strings
FORMULA_SAFE=$(echo "$TOTAL_COST_FORMULA" | sed 's/"/\\"/g' | tr -d '\n\r')

cat > /tmp/task_result.json << EOF
{
    "survey_found": $FOUND,
    "sid": "$SID",
    "active": "$ACTIVE",
    "questions": {
        "guests": {
            "exists": $GUESTS_Q_EXISTS,
            "type": "$GUESTS_Q_TYPE"
        },
        "package": {
            "exists": $PACKAGE_Q_EXISTS,
            "type": "$PACKAGE_Q_TYPE",
            "answer_codes": "$PACKAGE_ANSWER_CODES"
        },
        "total_cost": {
            "exists": $TOTAL_COST_Q_EXISTS,
            "type": "$TOTAL_COST_Q_TYPE",
            "formula": "$FORMULA_SAFE"
        }
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON content:"
cat /tmp/task_result.json

# Copy to final location for verifier
export_json_result "$(cat /tmp/task_result.json)" "/tmp/task_result.json"

echo "=== Export Complete ==="