#!/bin/bash
echo "=== Exporting SaaS Pricing Matrix Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. FIND THE SURVEY
# We look for the specific title requested
SURVEY_ID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%SaaS Pricing Strategy 2026%' LIMIT 1")

FOUND="false"
Q1_FOUND="false"
Q2_FOUND="false"
Q1_HTML=""
Q1_TYPE=""
Q2_TYPE=""
Q2_EXCLUSIVE_ATTR=""
Q2_EXCLUSIVE_CODE=""
Q2_NO_INTEG_CODE=""

if [ -n "$SURVEY_ID" ]; then
    FOUND="true"
    echo "Found Survey ID: $SURVEY_ID"

    # 2. EXTRACT QUESTION 1 (PREF) - HTML Content
    # We join questions and l10ns to get the actual text
    Q1_DATA=$(limesurvey_query "SELECT q.qid, q.type, l.question 
        FROM lime_questions q 
        JOIN lime_question_l10ns l ON q.qid = l.qid 
        WHERE q.sid = $SURVEY_ID AND q.title = 'PREF' LIMIT 1")
    
    if [ -n "$Q1_DATA" ]; then
        Q1_FOUND="true"
        Q1_ID=$(echo "$Q1_DATA" | cut -f1)
        Q1_TYPE=$(echo "$Q1_DATA" | cut -f2)
        # The HTML content might contain tabs/newlines, so we extract it carefully
        # We'll rely on python for robust extraction in the verifier if we pass the raw string,
        # but here we'll grab the raw output.
        # Note: mysql -N output is tab separated. The 3rd field is the question text.
        Q1_HTML=$(echo "$Q1_DATA" | cut -f3-)
    fi

    # 3. EXTRACT QUESTION 2 (INTEG) - Attributes
    Q2_DATA=$(limesurvey_query "SELECT qid, type FROM lime_questions WHERE sid = $SURVEY_ID AND title = 'INTEG' LIMIT 1")
    
    if [ -n "$Q2_DATA" ]; then
        Q2_FOUND="true"
        Q2_ID=$(echo "$Q2_DATA" | cut -f1)
        Q2_TYPE=$(echo "$Q2_DATA" | cut -f2)
        
        # Get the answer code for "No integrations needed"
        # We need this to check if the exclusive attribute matches this code
        Q2_NO_INTEG_CODE=$(limesurvey_query "SELECT a.code 
            FROM lime_answers a 
            JOIN lime_answer_l10ns l ON a.qid = l.qid AND a.code = l.code
            WHERE a.qid = $Q2_ID AND l.answer LIKE '%No integrations%' LIMIT 1")
        
        # Get the 'exclusive_option' attribute for this question
        # In LimeSurvey, multiple choice exclusion is stored in lime_question_attributes
        # attribute name is 'exclusive_option', value is the subquestion code
        Q2_EXCLUSIVE_ATTR=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid = $Q2_ID AND attribute = 'exclusive_option' LIMIT 1")
        
        echo "Q2 ID: $Q2_ID"
        echo "Q2 Type: $Q2_TYPE"
        echo "No Integ Code: $Q2_NO_INTEG_CODE"
        echo "Exclusive Attr Value: $Q2_EXCLUSIVE_ATTR"
    fi
fi

# Sanitize HTML for JSON (escape quotes and newlines)
# We use python to create the JSON to avoid bash string hell
python3 -c "
import json
import sys

data = {
    'survey_found': '$FOUND' == 'true',
    'survey_id': '$SURVEY_ID',
    'q1': {
        'found': '$Q1_FOUND' == 'true',
        'type': '$Q1_TYPE',
        'html_content': sys.stdin.read()  # Read Q1 HTML from stdin
    },
    'q2': {
        'found': '$Q2_FOUND' == 'true',
        'type': '$Q2_TYPE',
        'no_integ_code': '$Q2_NO_INTEG_CODE',
        'exclusive_attr_value': '$Q2_EXCLUSIVE_ATTR'
    }
}
print(json.dumps(data, indent=2))
" <<< "$Q1_HTML" > /tmp/task_result_raw.json

# Safe move
mv /tmp/task_result_raw.json /tmp/task_result.json 2>/dev/null || \
    sudo mv /tmp/task_result_raw.json /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

cat /tmp/task_result.json
echo "=== Export Complete ==="