#!/bin/bash
echo "=== Exporting Admin Response Correction Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Survey ID
SID=$(cat /tmp/task_survey_sid 2>/dev/null || \
      limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title = 'IT Service Desk Satisfaction 2025' LIMIT 1")

if [ -z "$SID" ]; then
    echo "Error: Survey ID not found."
    # Create empty error result
    echo '{"error": "Survey not found"}' > /tmp/task_result.json
    exit 0
fi

echo "Survey ID: $SID"

# We need to find the column names for Email, Satisfaction, and Comments.
# They follow the pattern SID X GID X QID.
# Let's query the questions table to get QIDs for our codes QEMAIL, QSAT, QCOM.
QEMAIL_ID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='QEMAIL' LIMIT 1")
QSAT_ID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='QSAT' LIMIT 1")
QCOM_ID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='QCOM' LIMIT 1")
GID=$(limesurvey_query "SELECT gid FROM lime_questions WHERE qid=$QEMAIL_ID LIMIT 1")

# Construct column names
COL_EMAIL="${SID}X${GID}X${QEMAIL_ID}"
COL_SAT="${SID}X${GID}X${QSAT_ID}"
COL_COM="${SID}X${GID}X${QCOM_ID}"

echo "Columns: Email=$COL_EMAIL, Sat=$COL_SAT, Com=$COL_COM"

# Query the response for Michael Chang
# We fetch ID, Satisfaction value, and Comment
RESPONSE_DATA=$(limesurvey_query "SELECT id, \`$COL_SAT\`, \`$COL_COM\` FROM lime_survey_$SID WHERE \`$COL_EMAIL\` = 'michael.chang@acmecorp.com' LIMIT 1")

FOUND="false"
RESP_ID=""
SAT_VAL=""
COM_VAL=""

if [ -n "$RESPONSE_DATA" ]; then
    FOUND="true"
    # Parse tab-separated output
    RESP_ID=$(echo "$RESPONSE_DATA" | awk -F'\t' '{print $1}')
    SAT_VAL=$(echo "$RESPONSE_DATA" | awk -F'\t' '{print $2}')
    # Comments might contain tabs/newlines, so we handle carefully. 
    # For simple export, awk $3-end is okay but safer to just query comment specifically if needed.
    # Let's use python for safer extraction of the comment field which might have special chars
    
    # Extract robustly using python db query
    python3 -c "
import mysql.connector
import json

try:
    conn = mysql.connector.connect(user='limesurvey', password='limesurvey_pass', host='limesurvey-db', database='limesurvey')
    cursor = conn.cursor()
    query = f\"SELECT id, \`{COL_SAT}\`, \`{COL_COM}\` FROM lime_survey_{SID} WHERE \`{COL_EMAIL}\` = 'michael.chang@acmecorp.com' LIMIT 1\"
    cursor.execute(query)
    row = cursor.fetchone()
    
    result = {
        'found': True if row else False,
        'response_id': row[0] if row else None,
        'satisfaction': row[1] if row else None,
        'comment': row[2] if row else None,
        'sid': '$SID'
    }
except Exception as e:
    result = {'found': False, 'error': str(e)}

with open('/tmp/response_data.json', 'w') as f:
    json.dump(result, f)
"
    # Merge with shell variables
    FOUND="true"
else
    echo '{"found": false}' > /tmp/response_data.json
fi

# Final JSON construction
# We load the python output
cp /tmp/response_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported Data:"
cat /tmp/task_result.json
echo "=== Export Complete ==="