#!/bin/bash
echo "=== Exporting Cognitive Timed Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. FIND THE SURVEY
# We look for the most recently created survey with "Executive Function" in the title
SURVEY_QUERY="SELECT s.sid, sl.surveyls_title, s.allowprev, s.showprogress 
              FROM lime_surveys s 
              JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
              WHERE sl.surveyls_title LIKE '%Executive Function%' 
              ORDER BY s.datecreated DESC LIMIT 1"

SURVEY_DATA=$(limesurvey_query "$SURVEY_QUERY" 2>/dev/null)

FOUND="false"
SID=""
TITLE=""
ALLOW_PREV=""
SHOW_PROGRESS=""

if [ -n "$SURVEY_DATA" ]; then
    FOUND="true"
    SID=$(echo "$SURVEY_DATA" | cut -f1)
    TITLE=$(echo "$SURVEY_DATA" | cut -f2)
    ALLOW_PREV=$(echo "$SURVEY_DATA" | cut -f3)
    SHOW_PROGRESS=$(echo "$SURVEY_DATA" | cut -f4)
    echo "Found Survey: SID=$SID, Title='$TITLE', AllowPrev=$ALLOW_PREV, Progress=$SHOW_PROGRESS"
else
    echo "Survey not found."
fi

# 2. GET QUESTION DETAILS (EF01)
Q1_FOUND="false"
Q1_ID=""
Q1_ATTRIBUTES="{}"

if [ "$FOUND" = "true" ]; then
    # Get QID for EF01
    Q1_ID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='EF01' LIMIT 1" 2>/dev/null)
    
    if [ -n "$Q1_ID" ]; then
        Q1_FOUND="true"
        # Get attributes for Q1
        # Attributes stored as rows: attribute, value
        # We'll fetch them and construct a JSON object string
        ATTR_DATA=$(limesurvey_query "SELECT attribute, value FROM lime_question_attributes WHERE qid=$Q1_ID" 2>/dev/null)
        
        # Parse attributes into JSON
        # Example output of query:
        # time_limit    10
        # random_order  1
        Q1_ATTRIBUTES=$(echo "$ATTR_DATA" | awk '
            BEGIN { printf "{"; first=1 }
            {
                if (!first) printf ",";
                printf "\"%s\": \"%s\"", $1, $2;
                first=0;
            }
            END { printf "}" }
        ')
    fi
fi

# 3. GET QUESTION DETAILS (EF02)
Q2_FOUND="false"
Q2_ID=""
Q2_ATTRIBUTES="{}"

if [ "$FOUND" = "true" ]; then
    Q2_ID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='EF02' LIMIT 1" 2>/dev/null)
    
    if [ -n "$Q2_ID" ]; then
        Q2_FOUND="true"
        ATTR_DATA=$(limesurvey_query "SELECT attribute, value FROM lime_question_attributes WHERE qid=$Q2_ID" 2>/dev/null)
        
        Q2_ATTRIBUTES=$(echo "$ATTR_DATA" | awk '
            BEGIN { printf "{"; first=1 }
            {
                if (!first) printf ",";
                printf "\"%s\": \"%s\"", $1, $2;
                first=0;
            }
            END { printf "}" }
        ')
    fi
fi

# 4. EXPORT JSON
# Using python to create safe JSON to avoid quoting issues
python3 << EOF
import json
import os

data = {
    "survey_found": $FOUND,
    "sid": "$SID",
    "title": "$TITLE",
    "allow_prev": "$ALLOW_PREV",
    "show_progress": "$SHOW_PROGRESS",
    "q1": {
        "found": $Q1_FOUND,
        "qid": "$Q1_ID",
        "attributes": json.loads('$Q1_ATTRIBUTES') if '$Q1_ATTRIBUTES' else {}
    },
    "q2": {
        "found": $Q2_FOUND,
        "qid": "$Q2_ID",
        "attributes": json.loads('$Q2_ATTRIBUTES') if '$Q2_ATTRIBUTES' else {}
    },
    "timestamp": "$(date -Iseconds)"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(data, f, indent=4)
EOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json