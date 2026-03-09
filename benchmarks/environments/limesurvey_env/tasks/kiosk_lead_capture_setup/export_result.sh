#!/bin/bash
echo "=== Exporting Kiosk Lead Capture Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Find the Survey ID
SURVEY_TITLE="TechInnovate 2026 Lead Capture"
SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title = '$SURVEY_TITLE' ORDER BY surveyls_survey_id DESC LIMIT 1" 2>/dev/null || echo "")

SURVEY_FOUND="false"
SETTINGS_JSON="{}"
QUESTIONS_JSON="[]"
ATTRIBUTES_JSON="{}"

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey ID: $SID"

    # 2. Get Survey Settings (Privacy, Cookies, Redirect)
    # ipaddr: Y/N
    # usecookie: Y/N
    # allowsave: Y/N (Participant may save and resume)
    # autoredirect: Y/N
    # active: Y/N
    SETTINGS_RAW=$(limesurvey_query "SELECT ipaddr, usecookie, allowsave, autoredirect, active FROM lime_surveys WHERE sid=$SID")
    
    # Get Redirect URL
    REDIRECT_URL=$(limesurvey_query "SELECT surveyls_url FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='en' LIMIT 1")

    # Construct Settings JSON
    read IPADDR USECOOKIE ALLOWSAVE AUTOREDIRECT ACTIVE <<< "$SETTINGS_RAW"
    SETTINGS_JSON=$(cat <<EOF
{
    "sid": "$SID",
    "ipaddr": "$IPADDR",
    "usecookie": "$USECOOKIE",
    "allowsave": "$ALLOWSAVE",
    "autoredirect": "$AUTOREDIRECT",
    "active": "$ACTIVE",
    "redirect_url": "$REDIRECT_URL"
}
EOF
)

    # 3. Get Questions
    # We need to check for Name, Email, and CaptureTime
    # Type '*' is usually Equation in LimeSurvey DB (or sometimes strictly 'Equation' depending on version, usually type column is char(1) or similar code. Equation is often '*')
    # Let's get code, type, question text
    
    # Note: question text is in lime_question_l10ns in newer versions, or lime_questions in older. The env seems to have lime_question_l10ns.
    # We join tables to get everything.
    QUESTIONS_LIST=$(limesurvey_query "SELECT q.qid, q.title, q.type, l.question 
        FROM lime_questions q 
        JOIN lime_question_l10ns l ON q.qid = l.qid 
        WHERE q.sid=$SID AND q.parent_qid=0")
    
    # Process into JSON array manually or via python helper
    # We'll just dump the raw string for the verifier to parse or simple bash array construction
    # Let's use a python one-liner to format it safely
    QUESTIONS_JSON=$(echo "$QUESTIONS_LIST" | python3 -c '
import sys, json
lines = sys.stdin.readlines()
questions = []
for line in lines:
    parts = line.strip().split("\t")
    if len(parts) >= 4:
        questions.append({"qid": parts[0], "title": parts[1], "type": parts[2], "text": parts[3]})
print(json.dumps(questions))
')

    # 4. Check Question Attributes (for "hidden")
    # specifically for the CaptureTime question
    # We look for attribute "hidden" with value "1"
    HIDDEN_ATTRS=$(limesurvey_query "SELECT q.title, a.attribute, a.value 
        FROM lime_question_attributes a 
        JOIN lime_questions q ON a.qid = q.qid 
        WHERE q.sid=$SID AND a.attribute='hidden'")
    
    ATTRIBUTES_JSON=$(echo "$HIDDEN_ATTRS" | python3 -c '
import sys, json
lines = sys.stdin.readlines()
attrs = {}
for line in lines:
    parts = line.strip().split("\t")
    if len(parts) >= 3:
        attrs[parts[0]] = {"attribute": parts[1], "value": parts[2]}
print(json.dumps(attrs))
')

fi

# Assemble final JSON
cat > /tmp/task_result.json <<EOF
{
    "survey_found": $SURVEY_FOUND,
    "settings": $SETTINGS_JSON,
    "questions": $QUESTIONS_JSON,
    "attributes": $ATTRIBUTES_JSON,
    "timestamp": "$(date +%s)"
}
EOF

# Fix permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json