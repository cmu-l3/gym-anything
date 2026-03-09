#!/bin/bash
set -e
echo "=== Exporting Label Set Concept Test Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for DB queries
DB_QUERY() {
    docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
}

# Helper to escape JSON strings
json_escape() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r'
}

# 1. Get Initial Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_SURVEY_COUNT=$(cat /tmp/initial_survey_count.txt 2>/dev/null || echo "0")
INITIAL_LABELSET_COUNT=$(cat /tmp/initial_labelset_count.txt 2>/dev/null || echo "0")

# 2. Check Current Counts
CURRENT_SURVEY_COUNT=$(DB_QUERY "SELECT COUNT(*) FROM lime_surveys" || echo "0")
CURRENT_LABELSET_COUNT=$(DB_QUERY "SELECT COUNT(*) FROM lime_labelsets" || echo "0")

# 3. Verify Label Sets
# Find "7-Point Satisfaction Scale"
SAT_DATA=$(DB_QUERY "SELECT lid, label_name FROM lime_labelsets WHERE LOWER(label_name) LIKE '%7%point%' OR LOWER(label_name) LIKE '%satisfaction%' LIMIT 1")
SAT_LID=$(echo "$SAT_DATA" | awk '{print $1}')
SAT_NAME=$(echo "$SAT_DATA" | cut -f2-)
SAT_LABEL_COUNT=0
SAT_LABELS_TEXT=""

if [ -n "$SAT_LID" ]; then
    SAT_LABEL_COUNT=$(DB_QUERY "SELECT COUNT(*) FROM lime_labels WHERE lid=$SAT_LID")
    # Get all labels text concatenated
    SAT_LABELS_TEXT=$(DB_QUERY "SELECT ll.title FROM lime_labels l JOIN lime_label_l10ns ll ON l.id = ll.label_id WHERE l.lid=$SAT_LID ORDER BY l.sortorder" | tr '\n' ';')
fi

# Find "5-Point Purchase Intent Scale"
PI_DATA=$(DB_QUERY "SELECT lid, label_name FROM lime_labelsets WHERE LOWER(label_name) LIKE '%5%point%' OR LOWER(label_name) LIKE '%purchase%' LIMIT 1")
PI_LID=$(echo "$PI_DATA" | awk '{print $1}')
PI_NAME=$(echo "$PI_DATA" | cut -f2-)
PI_LABEL_COUNT=0
PI_LABELS_TEXT=""

if [ -n "$PI_LID" ]; then
    PI_LABEL_COUNT=$(DB_QUERY "SELECT COUNT(*) FROM lime_labels WHERE lid=$PI_LID")
    PI_LABELS_TEXT=$(DB_QUERY "SELECT ll.title FROM lime_labels l JOIN lime_label_l10ns ll ON l.id = ll.label_id WHERE l.lid=$PI_LID ORDER BY l.sortorder" | tr '\n' ';')
fi

# 4. Verify Survey
SURVEY_SID=""
SURVEY_TITLE=""
SURVEY_ACTIVE="N"
SURVEY_ANONYMIZED="N"
GROUP_COUNT=0

# Try to find specific survey
SURVEY_DATA=$(DB_QUERY "SELECT s.sid, sl.surveyls_title, s.active, s.anonymized 
    FROM lime_surveys s 
    JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
    WHERE LOWER(sl.surveyls_title) LIKE '%concept test%' OR LOWER(sl.surveyls_title) LIKE '%sparkling water%' 
    ORDER BY s.datecreated DESC LIMIT 1")

if [ -n "$SURVEY_DATA" ]; then
    SURVEY_SID=$(echo "$SURVEY_DATA" | cut -f1)
    SURVEY_TITLE=$(echo "$SURVEY_DATA" | cut -f2)
    SURVEY_ACTIVE=$(echo "$SURVEY_DATA" | cut -f3)
    SURVEY_ANONYMIZED=$(echo "$SURVEY_DATA" | cut -f4)
    
    GROUP_COUNT=$(DB_QUERY "SELECT COUNT(*) FROM lime_groups WHERE sid=$SURVEY_SID")
else
    # Fallback: check ANY new survey if specific title missing
    if [ "$CURRENT_SURVEY_COUNT" -gt "$INITIAL_SURVEY_COUNT" ]; then
        SURVEY_SID=$(DB_QUERY "SELECT sid FROM lime_surveys ORDER BY sid DESC LIMIT 1")
    fi
fi

# 5. Verify Questions (if survey found)
Q_APPEAL_FOUND="false"
Q_APPEAL_SUBQ_COUNT=0
Q_APPEAL_ANSWERS=""
Q_PURCHASE_FOUND="false"
Q_PURCHASE_SUBQ_COUNT=0
Q_PURCHASE_ANSWERS=""

if [ -n "$SURVEY_SID" ]; then
    # Get all array questions (Type F, H, :, ;)
    # We check each to see if it matches our expectations
    QIDS=$(DB_QUERY "SELECT qid FROM lime_questions WHERE sid=$SURVEY_SID AND parent_qid=0 AND type IN ('F','H',':',';')")
    
    for QID in $QIDS; do
        # Check text/title to identify question
        Q_TEXT=$(DB_QUERY "SELECT question FROM lime_question_l10ns WHERE qid=$QID")
        Q_CODE=$(DB_QUERY "SELECT title FROM lime_questions WHERE qid=$QID")
        SUBQ_COUNT=$(DB_QUERY "SELECT COUNT(*) FROM lime_questions WHERE parent_qid=$QID")
        ANSWERS=$(DB_QUERY "SELECT answer FROM lime_answer_l10ns WHERE aid IN (SELECT aid FROM lime_answers WHERE qid=$QID)" | tr '\n' ';')
        
        # Check if it looks like the Appeal question (6 subqs or contains "satisfied")
        if echo "$Q_TEXT" | grep -qi "satisfied" || echo "$Q_CODE" | grep -qi "APPEAL" || [ "$SUBQ_COUNT" -ge 6 ]; then
            Q_APPEAL_FOUND="true"
            Q_APPEAL_SUBQ_COUNT=$SUBQ_COUNT
            Q_APPEAL_ANSWERS=$ANSWERS
        fi
        
        # Check if it looks like the Purchase question (4 subqs or contains "purchase")
        if echo "$Q_TEXT" | grep -qi "purchase" || echo "$Q_CODE" | grep -qi "PURCHASE" || ([ "$SUBQ_COUNT" -ge 4 ] && [ "$SUBQ_COUNT" -lt 6 ]); then
            Q_PURCHASE_FOUND="true"
            Q_PURCHASE_SUBQ_COUNT=$SUBQ_COUNT
            Q_PURCHASE_ANSWERS=$ANSWERS
        fi
    done
fi

# 6. Take final screenshot
take_screenshot /tmp/task_final.png

# 7. Generate JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "initial_survey_count": $INITIAL_SURVEY_COUNT,
    "current_survey_count": $CURRENT_SURVEY_COUNT,
    "initial_labelset_count": $INITIAL_LABELSET_COUNT,
    "current_labelset_count": $CURRENT_LABELSET_COUNT,
    
    "satisfaction_labelset": {
        "lid": "$(json_escape "$SAT_LID")",
        "name": "$(json_escape "$SAT_NAME")",
        "count": $SAT_LABEL_COUNT,
        "labels": "$(json_escape "$SAT_LABELS_TEXT")"
    },
    
    "purchase_labelset": {
        "lid": "$(json_escape "$PI_LID")",
        "name": "$(json_escape "$PI_NAME")",
        "count": $PI_LABEL_COUNT,
        "labels": "$(json_escape "$PI_LABELS_TEXT")"
    },
    
    "survey": {
        "sid": "$(json_escape "$SURVEY_SID")",
        "title": "$(json_escape "$SURVEY_TITLE")",
        "active": "$(json_escape "$SURVEY_ACTIVE")",
        "anonymized": "$(json_escape "$SURVEY_ANONYMIZED")",
        "group_count": $GROUP_COUNT
    },
    
    "questions": {
        "appeal_found": $Q_APPEAL_FOUND,
        "appeal_subq_count": $Q_APPEAL_SUBQ_COUNT,
        "appeal_answers": "$(json_escape "$Q_APPEAL_ANSWERS")",
        "purchase_found": $Q_PURCHASE_FOUND,
        "purchase_subq_count": $Q_PURCHASE_SUBQ_COUNT,
        "purchase_answers": "$(json_escape "$Q_PURCHASE_ANSWERS")"
    }
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json