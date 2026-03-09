#!/bin/bash
echo "=== Exporting Burnout Assessment Results ==="

source /workspace/scripts/task_utils.sh

# Helper for DB queries
db_query() {
    docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
}

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Find the created survey
echo "Finding survey..."
# Look for newest survey matching keywords
SURVEY_DATA=$(db_query "SELECT s.sid, sl.surveyls_title, s.assessments, s.active 
FROM lime_surveys s 
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
WHERE sl.surveyls_title LIKE '%Burnout%' OR sl.surveyls_title LIKE '%CBI%' 
ORDER BY s.datecreated DESC LIMIT 1")

SURVEY_FOUND="false"
SID=""
TITLE=""
ASSESSMENTS_MODE=""
ACTIVE=""

if [ -n "$SURVEY_DATA" ]; then
    SURVEY_FOUND="true"
    SID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    # Extract title (everything between first tab and next tab)
    TITLE=$(echo "$SURVEY_DATA" | cut -f2)
    ASSESSMENTS_MODE=$(echo "$SURVEY_DATA" | cut -f3)
    ACTIVE=$(echo "$SURVEY_DATA" | cut -f4)
    echo "Found Survey: SID=$SID, Title='$TITLE', Assessments='$ASSESSMENTS_MODE', Active='$ACTIVE'"
else
    echo "No matching survey found."
fi

# 2. Check Question Groups
GROUP_COUNT=0
if [ "$SURVEY_FOUND" = "true" ]; then
    GROUP_COUNT=$(db_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID")
fi

# 3. Check Array Question & Subquestions
ARRAY_QID=""
SUBQUESTION_COUNT=0
MANDATORY=""
if [ "$SURVEY_FOUND" = "true" ]; then
    # Find Array question (Type F, H, etc.)
    # We look for the one with the most subquestions if multiple exist
    Q_DATA=$(db_query "SELECT qid, mandatory FROM lime_questions WHERE sid=$SID AND parent_qid=0 AND type IN ('F','H','1','A','B','C','E') LIMIT 1")
    
    if [ -n "$Q_DATA" ]; then
        ARRAY_QID=$(echo "$Q_DATA" | awk '{print $1}')
        MANDATORY=$(echo "$Q_DATA" | awk '{print $2}')
        
        # Count subquestions
        SUBQUESTION_COUNT=$(db_query "SELECT COUNT(*) FROM lime_questions WHERE parent_qid=$ARRAY_QID")
    fi
fi

# 4. Check Assessment Values
ASSESSMENT_VALUES_JSON="[]"
if [ -n "$ARRAY_QID" ]; then
    # Get distinct non-zero assessment values
    VALS=$(db_query "SELECT DISTINCT assessment_value FROM lime_answers WHERE qid=$ARRAY_QID ORDER BY assessment_value")
    # Convert to JSON array
    ASSESSMENT_VALUES_JSON=$(echo "$VALS" | jq -R . | jq -s .)
fi

# 5. Check Assessment Rules
RULE_COUNT=0
RULES_JSON="[]"
if [ "$SURVEY_FOUND" = "true" ]; then
    # Structure of lime_assessments: id, sid, scope, gid, minimum, maximum, message, ...
    # Note: message might be in a l10n table depending on version, but usually 'message' column exists in older or direct logic
    # We'll just grab min/max which are critical
    RULES_DATA=$(db_query "SELECT minimum, maximum FROM lime_assessments WHERE sid=$SID")
    RULE_COUNT=$(echo "$RULES_DATA" | grep -v "^$" | wc -l)
    
    if [ -n "$RULES_DATA" ]; then
        # Create JSON array of objects
        RULES_JSON=$(echo "$RULES_DATA" | awk '{print "{\"min\": "$1", \"max\": "$2"}"}' | jq -s .)
    fi
fi

# Timestamp check for anti-gaming
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# Create result JSON
cat > /tmp/task_result.json <<EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "title": "$(echo $TITLE | sed 's/"/\\"/g')",
    "assessments_enabled": "$ASSESSMENTS_MODE",
    "active": "$ACTIVE",
    "group_count": $GROUP_COUNT,
    "array_qid": "$ARRAY_QID",
    "subquestion_count": $SUBQUESTION_COUNT,
    "mandatory": "$MANDATORY",
    "assessment_values": $ASSESSMENT_VALUES_JSON,
    "rule_count": $RULE_COUNT,
    "rules": $RULES_JSON,
    "task_start_ts": $TASK_START,
    "export_ts": $NOW
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="