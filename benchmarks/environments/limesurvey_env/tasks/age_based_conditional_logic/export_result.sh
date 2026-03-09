#!/bin/bash
echo "=== Exporting Age-Based Logic Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get survey ID based on title
# We search for "Influenza" or "Vaccine" as keywords
SURVEY_DATA=$(limesurvey_query "SELECT s.sid, sl.surveyls_title, s.active 
FROM lime_surveys s 
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
WHERE LOWER(sl.surveyls_title) LIKE '%influenza%' OR LOWER(sl.surveyls_title) LIKE '%vaccine%' 
ORDER BY s.datecreated DESC LIMIT 1")

FOUND="false"
SID=""
TITLE=""
ACTIVE="N"
DOB_Q_EXISTS="false"
CALC_Q_EXISTS="false"
CALC_EQUATION=""
GROUPS_JSON="[]"
GROUP_COUNT=0

if [ -n "$SURVEY_DATA" ]; then
    FOUND="true"
    SID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    # Extract title handling spaces (everything between first space and last column)
    TITLE=$(echo "$SURVEY_DATA" | cut -d' ' -f2- | rev | cut -d' ' -f2- | rev)
    ACTIVE=$(echo "$SURVEY_DATA" | awk '{print $NF}')
    
    echo "Found Survey: $SID - $TITLE (Active: $ACTIVE)"
    
    # 1. Check Questions (DOB and AGE_CALC)
    # Get DOB Question
    DOB_CHECK=$(limesurvey_query "SELECT type, title FROM lime_questions WHERE sid=$SID AND title='DOB' LIMIT 1")
    if [ -n "$DOB_CHECK" ]; then
        DOB_TYPE=$(echo "$DOB_CHECK" | awk '{print $1}')
        if [ "$DOB_TYPE" == "D" ]; then
            DOB_Q_EXISTS="true"
        fi
    fi
    
    # Get Calculation Question (Equation)
    # Note: question text for equation type '*' contains the actual logic
    CALC_CHECK=$(limesurvey_query "SELECT q.type, ql.question 
    FROM lime_questions q 
    JOIN lime_question_l10ns ql ON q.qid = ql.qid 
    WHERE q.sid=$SID AND q.title='AGE_CALC' LIMIT 1")
    
    if [ -n "$CALC_CHECK" ]; then
        CALC_TYPE=$(echo "$CALC_CHECK" | awk '{print $1}')
        # Extract equation text (everything after type)
        CALC_EQUATION=$(echo "$CALC_CHECK" | cut -d' ' -f2-)
        
        if [ "$CALC_TYPE" == "*" ]; then
            CALC_Q_EXISTS="true"
        fi
    fi
    
    # 2. Check Groups and Relevance
    # We export group details to JSON for Python to parse the complex relevance string
    # We use a python one-liner to fetch and format group data because raw bash parsing of SQL with special chars is fragile
    
    GROUPS_JSON=$(python3 -c "
import mysql.connector
import json

try:
    conn = mysql.connector.connect(user='limesurvey', password='limesurvey_pass', host='limesurvey-db', database='limesurvey')
    cursor = conn.cursor(dictionary=True)
    cursor.execute('SELECT gid, group_name, grelevance, group_order FROM lime_groups WHERE sid=$SID ORDER BY group_order')
    groups = cursor.fetchall()
    
    # Get question count per group
    for g in groups:
        cursor.execute(f'SELECT COUNT(*) as count FROM lime_questions WHERE gid={g[\"gid\"]} AND parent_qid=0')
        g[\"question_count\"] = cursor.fetchone()[\"count\"]
        
        # Clean strings
        if g[\"grelevance\"] is None: g[\"grelevance\"] = \"\"
        g[\"grelevance\"] = str(g[\"grelevance\"])
        
    print(json.dumps(groups))
except Exception as e:
    print('[]')
")
    
    GROUP_COUNT=$(echo "$GROUPS_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
fi

# Sanitize equation for JSON inclusion
CALC_EQUATION_ESCAPED=$(echo "$CALC_EQUATION" | sed 's/"/\\"/g' | tr -d '\n')

# Construct Result JSON
cat > /tmp/task_result.json << EOF
{
    "survey_found": $FOUND,
    "survey_id": "$SID",
    "survey_title": "$TITLE",
    "active": "$ACTIVE",
    "dob_question_exists": $DOB_Q_EXISTS,
    "calc_question_exists": $CALC_Q_EXISTS,
    "calc_equation": "$CALC_EQUATION_ESCAPED",
    "group_count": $GROUP_COUNT,
    "groups": $GROUPS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe file permission handling
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json