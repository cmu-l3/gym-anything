#!/bin/bash
echo "=== Exporting Fellowship Application Task Result ==="

source /workspace/scripts/task_utils.sh

# Fallback query function
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Find the target survey
# Looking for "2026 Doctoral Research Fellowship"
SURVEY_DATA=$(limesurvey_query "
    SELECT s.sid, s.allowsave, sl.surveyls_title, sl.surveyls_email_saved_subj
    FROM lime_surveys s
    JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id
    WHERE sl.surveyls_title LIKE '%Doctoral Research Fellowship%'
    ORDER BY s.datecreated DESC LIMIT 1
")

SURVEY_FOUND="false"
SID=""
ALLOW_SAVE="N"
TITLE=""
EMAIL_SUBJECT=""

if [ -n "$SURVEY_DATA" ]; then
    SURVEY_FOUND="true"
    # Parse tab-separated output
    SID=$(echo "$SURVEY_DATA" | awk -F'\t' '{print $1}')
    ALLOW_SAVE=$(echo "$SURVEY_DATA" | awk -F'\t' '{print $2}')
    TITLE=$(echo "$SURVEY_DATA" | awk -F'\t' '{print $3}')
    # Email subject is the 4th column, might contain spaces
    EMAIL_SUBJECT=$(echo "$SURVEY_DATA" | cut -f4)
    
    echo "Found Survey: SID=$SID, Title='$TITLE'"
fi

# 3. Check for the specific question ("Research Proposal" / code "proposal")
QUESTION_FOUND="false"
QID=""
Q_TYPE=""
Q_TITLE=""

if [ "$SURVEY_FOUND" = "true" ]; then
    Q_DATA=$(limesurvey_query "
        SELECT qid, type, title 
        FROM lime_questions 
        WHERE sid=$SID 
        AND (title='proposal' OR question LIKE '%Research Proposal%')
        LIMIT 1
    ")
    
    if [ -n "$Q_DATA" ]; then
        QUESTION_FOUND="true"
        QID=$(echo "$Q_DATA" | awk -F'\t' '{print $1}')
        Q_TYPE=$(echo "$Q_DATA" | awk -F'\t' '{print $2}')
        Q_TITLE=$(echo "$Q_DATA" | awk -F'\t' '{print $3}')
        echo "Found Question: QID=$QID, Type=$Q_TYPE"
    fi
fi

# 4. Check Question Attributes (File type, size, count)
ATTR_FILETYPES=""
ATTR_MAXSIZE=""
ATTR_MAXNUM=""

if [ "$QUESTION_FOUND" = "true" ]; then
    # allowed_filetypes
    ATTR_FILETYPES=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$QID AND attribute='allowed_filetypes'")
    # max_filesize
    ATTR_MAXSIZE=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$QID AND attribute='max_filesize'")
    # max_num_of_files
    ATTR_MAXNUM=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$QID AND attribute='max_num_of_files'")
fi

# 5. Sanitize strings for JSON
TITLE_SAFE=$(echo "$TITLE" | sed 's/"/\\"/g' | tr -d '\n\r')
EMAIL_SUBJECT_SAFE=$(echo "$EMAIL_SUBJECT" | sed 's/"/\\"/g' | tr -d '\n\r')
ATTR_FILETYPES_SAFE=$(echo "$ATTR_FILETYPES" | sed 's/"/\\"/g' | tr -d '\n\r')

# 6. Create JSON result
cat > /tmp/task_result.json << EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "title": "$TITLE_SAFE",
    "allow_save": "$ALLOW_SAVE",
    "email_subject": "$EMAIL_SUBJECT_SAFE",
    "question_found": $QUESTION_FOUND,
    "question_type": "$Q_TYPE",
    "question_code": "$Q_TITLE",
    "attr_filetypes": "$ATTR_FILETYPES_SAFE",
    "attr_maxsize": "$ATTR_MAXSIZE",
    "attr_maxnum": "$ATTR_MAXNUM",
    "timestamp": "$(date +%s)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="