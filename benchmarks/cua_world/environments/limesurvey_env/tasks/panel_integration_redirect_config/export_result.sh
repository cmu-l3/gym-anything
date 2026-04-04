#!/bin/bash
echo "=== Exporting Panel Integration Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Identify the survey ID
# We look for the specific title
SURVEY_TITLE="Enterprise Cloud Adoption 2024"
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE ls.surveyls_title='$SURVEY_TITLE' LIMIT 1")

echo "Found Survey ID: $SID"

# 3. Export Data for Verification

# A. URL Parameters
# Check table lime_survey_url_parameters
PARAM_COUNT=0
PARAM_NAME=""
if [ -n "$SID" ]; then
    PARAM_NAME=$(limesurvey_query "SELECT parameter FROM lime_survey_url_parameters WHERE sid=$SID AND parameter='rid' LIMIT 1")
    if [ -n "$PARAM_NAME" ]; then PARAM_COUNT=1; fi
fi

# B. Survey End URL & Auto-redirect
END_URL=""
AUTO_REDIRECT=""
if [ -n "$SID" ]; then
    END_URL=$(limesurvey_query "SELECT surveyls_url FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID")
    AUTO_REDIRECT=$(limesurvey_query "SELECT autoredirect FROM lime_surveys WHERE sid=$SID")
fi

# C. Quota Configuration
# We need to find a quota with limit 0
QUOTA_ID=""
QUOTA_LIMIT=""
QUOTA_URL=""
QUOTA_AUTOLOAD=""
QUOTA_MEMBER_CODE=""
QUOTA_QID=""

if [ -n "$SID" ]; then
    # Find quota with limit 0
    QUOTA_DATA=$(limesurvey_query "SELECT id, qlimit FROM lime_quotas WHERE sid=$SID AND qlimit=0 LIMIT 1")
    QUOTA_ID=$(echo "$QUOTA_DATA" | awk '{print $1}')
    QUOTA_LIMIT=$(echo "$QUOTA_DATA" | awk '{print $2}')

    if [ -n "$QUOTA_ID" ]; then
        # Get URL settings for this quota
        QUOTA_URL_DATA=$(limesurvey_query "SELECT quotals_url, quotals_autoload_url FROM lime_quotas_languagesettings WHERE quota_id=$QUOTA_ID LIMIT 1")
        # Split by tab
        QUOTA_URL=$(echo "$QUOTA_URL_DATA" | cut -f1)
        QUOTA_AUTOLOAD=$(echo "$QUOTA_URL_DATA" | cut -f2)

        # Get Member settings (Question link)
        # We verify it links to Q01 and answer 'N' (No)
        # Note: lime_quota_members links quota_id to qid and code
        MEMBER_DATA=$(limesurvey_query "SELECT qm.qid, qm.code FROM lime_quota_members qm WHERE qm.quota_id=$QUOTA_ID LIMIT 1")
        QUOTA_QID=$(echo "$MEMBER_DATA" | awk '{print $1}')
        QUOTA_MEMBER_CODE=$(echo "$MEMBER_DATA" | awk '{print $2}')
    fi
fi

# 4. Construct JSON Result
# Using python to construct JSON safely handles special chars in URLs
python3 << PYEOF
import json
import os

result = {
    "sid": "$SID",
    "param_exists": True if "$PARAM_NAME" == "rid" else False,
    "end_url": "$END_URL",
    "auto_redirect": "$AUTO_REDIRECT",
    "quota_found": True if "$QUOTA_ID" else False,
    "quota_limit": "$QUOTA_LIMIT",
    "quota_url": "$QUOTA_URL",
    "quota_autoload": "$QUOTA_AUTOLOAD",
    "quota_qid": "$QUOTA_QID",
    "quota_member_code": "$QUOTA_MEMBER_CODE",
    "screenshot_path": "/tmp/task_final.png"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move to safe location with permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json