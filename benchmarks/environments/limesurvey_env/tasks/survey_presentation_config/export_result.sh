#!/bin/bash
echo "=== Exporting Survey Configuration Result ==="

source /workspace/scripts/task_utils.sh

# Get SID
SID=$(cat /tmp/task_survey_id.txt 2>/dev/null)
if [ -z "$SID" ]; then
    # Fallback search
    SID=$(limesurvey_query "SELECT sid FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%TechSummit%' LIMIT 1")
fi

echo "Checking configuration for Survey ID: $SID"

# 1. Get Settings from lime_surveys
# Columns: format, showprogress, printanswers, allowprev, autoredirect
SETTINGS_ROW=$(limesurvey_query "SELECT format, showprogress, printanswers, allowprev, autoredirect FROM lime_surveys WHERE sid=$SID")

FORMAT=$(echo "$SETTINGS_ROW" | awk '{print $1}')
PROGRESS=$(echo "$SETTINGS_ROW" | awk '{print $2}')
PRINT=$(echo "$SETTINGS_ROW" | awk '{print $3}')
PREV=$(echo "$SETTINGS_ROW" | awk '{print $4}')
REDIRECT=$(echo "$SETTINGS_ROW" | awk '{print $5}')

# 2. Get Text/URL from lime_surveys_languagesettings
# We use python to safely handle potentially long text/html content from DB
TEXT_JSON=$(python3 - << PYEOF
import mysql.connector
import json

try:
    conn = mysql.connector.connect(
        host="limesurvey-db",
        user="limesurvey",
        password="limesurvey_pass",
        database="limesurvey"
    )
    cursor = conn.cursor()
    cursor.execute("SELECT surveyls_welcometext, surveyls_endtext, surveyls_url FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='en'")
    row = cursor.fetchone()
    if row:
        print(json.dumps({
            "welcome": row[0] if row[0] else "",
            "endtext": row[1] if row[1] else "",
            "url": row[2] if row[2] else ""
        }))
    else:
        print(json.dumps({"welcome": "", "endtext": "", "url": ""}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Combine into result JSON
cat > /tmp/task_result.json << EOF
{
    "sid": "$SID",
    "settings": {
        "format": "$FORMAT",
        "showprogress": "$PROGRESS",
        "printanswers": "$PRINT",
        "allowprev": "$PREV",
        "autoredirect": "$REDIRECT"
    },
    "text_content": $TEXT_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete:"
cat /tmp/task_result.json