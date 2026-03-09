#!/bin/bash
echo "=== Exporting Product Concept Survey Config Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the survey settings
# We need to find the specific survey by title
SURVEY_TITLE="Sparkling Water Concept Test - Wave 3"

# Find SID
SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title = '${SURVEY_TITLE}' LIMIT 1")

if [ -z "$SID" ]; then
    echo "Survey not found!"
    cat > /tmp/task_result.json << EOF
{
    "survey_found": false,
    "sid": null
}
EOF
else
    echo "Found Survey SID: $SID"

    # Get General/Presentation Settings from lime_surveys
    # Columns: format, showprogress, allowprev, shownoanswer, startdate, expires, emailnotificationto
    SETTINGS_ROW=$(limesurvey_query "SELECT format, showprogress, allowprev, shownoanswer, COALESCE(startdate, 'NULL'), COALESCE(expires, 'NULL'), COALESCE(emailnotificationto, '') FROM lime_surveys WHERE sid = $SID")
    
    # Parse space-separated (mysql -N output)
    # Note: Text fields might contain spaces, so we use a custom delimiter query if needed, 
    # but for these specific codes/dates it's usually fine. emailnotificationto might have spaces if multiple? 
    # Let's use specific queries for safety.

    FORMAT=$(limesurvey_query "SELECT format FROM lime_surveys WHERE sid=$SID")
    SHOW_PROGRESS=$(limesurvey_query "SELECT showprogress FROM lime_surveys WHERE sid=$SID")
    ALLOW_PREV=$(limesurvey_query "SELECT allowprev FROM lime_surveys WHERE sid=$SID")
    SHOW_NO_ANSWER=$(limesurvey_query "SELECT shownoanswer FROM lime_surveys WHERE sid=$SID")
    START_DATE=$(limesurvey_query "SELECT startdate FROM lime_surveys WHERE sid=$SID")
    EXPIRE_DATE=$(limesurvey_query "SELECT expires FROM lime_surveys WHERE sid=$SID")
    ADMIN_EMAIL=$(limesurvey_query "SELECT emailnotificationto FROM lime_surveys WHERE sid=$SID")

    # Get Text Settings from lime_surveys_languagesettings
    # These contain HTML/Text, so we must be careful with JSON escaping.
    # We will verify these in the python verifier by querying DB directly via docker exec if possible,
    # OR we export them to a temp file and read them.
    # Here we'll just dump them to a safe temp file to be read by Python script generation.
    
    # Actually, simpler: Use python to fetch and dump JSON directly to avoid bash quoting hell
    python3 << PYEOF
import json
import subprocess

def run_query(sql):
    cmd = ["docker", "exec", "limesurvey-db", "mysql", "-u", "limesurvey", "-plimesurvey_pass", "limesurvey", "-N", "-e", sql]
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        return res
    except:
        return ""

sid = "$SID"
data = {
    "survey_found": True,
    "sid": sid,
    "settings": {
        "format": run_query(f"SELECT format FROM lime_surveys WHERE sid={sid}"),
        "showprogress": run_query(f"SELECT showprogress FROM lime_surveys WHERE sid={sid}"),
        "allowprev": run_query(f"SELECT allowprev FROM lime_surveys WHERE sid={sid}"),
        "shownoanswer": run_query(f"SELECT shownoanswer FROM lime_surveys WHERE sid={sid}"),
        "startdate": run_query(f"SELECT startdate FROM lime_surveys WHERE sid={sid}"),
        "expires": run_query(f"SELECT expires FROM lime_surveys WHERE sid={sid}"),
        "emailnotificationto": run_query(f"SELECT emailnotificationto FROM lime_surveys WHERE sid={sid}")
    },
    "text": {
        "welcometext": run_query(f"SELECT surveyls_welcometext FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid}"),
        "endtext": run_query(f"SELECT surveyls_endtext FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid}"),
        "url": run_query(f"SELECT surveyls_url FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid}")
    }
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(data, f)
PYEOF

fi

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="