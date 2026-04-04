#!/bin/bash
echo "=== Exporting Public Event Registration Result ==="

source /workspace/scripts/task_utils.sh

# Fallback query function
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

SID=$(cat /tmp/task_sid 2>/dev/null || echo "")

# If SID lost, try to find it
if [ -z "$SID" ]; then
    SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE ls.surveyls_title LIKE '%Global Tech Summit%' LIMIT 1")
fi

echo "Checking Survey ID: $SID"

if [ -n "$SID" ]; then
    # 1. Check Public Registration Settings
    # allowregister: 'Y' means public registration allowed
    # registration_captcha: 'Y' means CAPTCHA enabled
    SETTINGS=$(limesurvey_query "SELECT allowregister, registration_captcha FROM lime_surveys WHERE sid=$SID")
    ALLOW_REGISTER=$(echo "$SETTINGS" | awk '{print $1}')
    USE_CAPTCHA=$(echo "$SETTINGS" | awk '{print $2}')

    # 2. Check Custom Attributes
    # Attributes are stored in lime_surveys_token_attributes (for newer LS) or lime_tokens_attribute
    # We check lime_surveys_token_attributes which maps attribute_id to survey_id
    
    # We need to query for attribute descriptions/names
    # Schema varies slightly by version, but usually:
    # lime_surveys_token_attributes: attribute_id, sid, attribute_name, description, mandatory, show_register
    
    ATTRIBUTES_JSON=$(limesurvey_query "SELECT description, attribute_name, mandatory, show_register FROM lime_surveys_token_attributes WHERE sid=$SID" | python3 -c '
import sys, json
attributes = []
for line in sys.stdin:
    parts = line.strip().split("\t")
    if len(parts) >= 4:
        attributes.append({
            "description": parts[0],
            "name": parts[1],
            "mandatory": parts[2],
            "show_register": parts[3]
        })
print(json.dumps(attributes))
')
    
    # If python script fails or table empty (no attributes created)
    if [ -z "$ATTRIBUTES_JSON" ]; then
        ATTRIBUTES_JSON="[]"
    fi

    SURVEY_FOUND="true"
else
    SURVEY_FOUND="false"
    ALLOW_REGISTER="N"
    USE_CAPTCHA="N"
    ATTRIBUTES_JSON="[]"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "allow_register": "$ALLOW_REGISTER",
    "use_captcha": "$USE_CAPTCHA",
    "attributes": $ATTRIBUTES_JSON,
    "timestamp": $(date +%s)
}
EOF

echo "Result JSON content:"
cat /tmp/task_result.json

# Cleanup
chown ga:ga /tmp/task_result.json 2>/dev/null || true
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="