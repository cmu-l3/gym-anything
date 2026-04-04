#!/bin/bash
echo "=== Exporting Token Custom Attributes Result ==="

source /workspace/scripts/task_utils.sh

# Helper for DB queries
db_query() {
    docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
}

# Capture final state
take_screenshot /tmp/task_final.png

# 1. Find the target survey
# Looking for "Post-Purchase" and "Satisfaction" in title
SID=$(db_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid = ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%post-purchase%' AND LOWER(ls.surveyls_title) LIKE '%satisfaction%' ORDER BY s.datecreated DESC LIMIT 1")

SURVEY_FOUND="false"
TOKEN_TABLE_EXISTS="false"
ATTRIBUTE_DESCRIPTIONS=""
PARTICIPANT_COUNT=0
ATTRIBUTES_POPULATED_COUNT=0
PARTICIPANT_DATA="[]"
GROUP_COUNT=0
QUESTION_COUNT=0

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey SID: $SID"

    # 2. Check for Token Table
    TABLE_CHECK=$(db_query "SHOW TABLES LIKE 'lime_tokens_$SID'")
    if [ -n "$TABLE_CHECK" ]; then
        TOKEN_TABLE_EXISTS="true"

        # 3. Check Attribute Columns (attribute_1, attribute_2, etc.)
        # We just need to know if columns exist, verification of mapping happens via attributedescriptions
        
        # 4. Get Attribute Descriptions from survey settings
        # LimeSurvey stores this in 'attributedescriptions' column in lime_surveys
        # It's often a serialized string or JSON
        ATTRIBUTE_DESCRIPTIONS=$(db_query "SELECT attributedescriptions FROM lime_surveys WHERE sid=$SID")

        # 5. Get Participant Count
        PARTICIPANT_COUNT=$(db_query "SELECT COUNT(*) FROM lime_tokens_$SID")

        # 6. Get Participant Data (Email + Attributes)
        # We select specific columns. Note: LimeSurvey uses attribute_1, attribute_2...
        # We'll fetch as a JSON-like CSV to parse in python
        # Check if attribute columns exist first to avoid SQL error
        COLS=$(db_query "SHOW COLUMNS FROM lime_tokens_$SID LIKE 'attribute_%'")
        if [ -n "$COLS" ]; then
            # Construct a safe query
            # We assume up to 4 attributes for this task
            RAW_DATA=$(db_query "SELECT email, firstname, lastname, attribute_1, attribute_2, attribute_3, attribute_4 FROM lime_tokens_$SID")
            
            # Count rows where all 4 attributes have values
            ATTRIBUTES_POPULATED_COUNT=$(db_query "SELECT COUNT(*) FROM lime_tokens_$SID WHERE attribute_1 != '' AND attribute_2 != '' AND attribute_3 != '' AND attribute_4 != ''")
            
            # simple CSV export for python to parse
            # Escape quotes in data
            PARTICIPANT_DATA=$(echo "$RAW_DATA" | python3 -c '
import sys, json, csv
reader = csv.reader(sys.stdin, delimiter="\t")
data = []
for row in reader:
    if len(row) >= 7:
        data.append({
            "email": row[0],
            "firstname": row[1],
            "lastname": row[2],
            "attr_1": row[3],
            "attr_2": row[4],
            "attr_3": row[5],
            "attr_4": row[6]
        })
print(json.dumps(data))
')
        fi
    fi

    # 7. Check Structure
    GROUP_COUNT=$(db_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID")
    QUESTION_COUNT=$(db_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0")
fi

# Create Result JSON
cat > /tmp/task_result_temp.json << EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "token_table_exists": $TOKEN_TABLE_EXISTS,
    "attribute_descriptions_raw": $(echo "$ATTRIBUTE_DESCRIPTIONS" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read().strip()))'),
    "participant_count": ${PARTICIPANT_COUNT:-0},
    "attributes_populated_count": ${ATTRIBUTES_POPULATED_COUNT:-0},
    "participants": ${PARTICIPANT_DATA:-[]},
    "group_count": ${GROUP_COUNT:-0},
    "question_count": ${QUESTION_COUNT:-0},
    "timestamp": "$(date +%s)"
}
EOF

# Move to final location
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json