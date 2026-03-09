#!/bin/bash
echo "=== Exporting CPDB Task Result ==="

source /workspace/scripts/task_utils.sh

# Helper for queries
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# 1. Get Target Survey ID
SID=$(cat /tmp/target_survey_id.txt 2>/dev/null || \
      limesurvey_query "SELECT sid FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Brand Perception Tracker%' LIMIT 1")

# 2. Query CPDB Participants
echo "Querying participants..."
# Get JSON-like output from MySQL using CONCAT
PARTICIPANTS_JSON=$(docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "
SELECT CONCAT(
    '[', 
    GROUP_CONCAT(
        JSON_OBJECT(
            'participant_id', participant_id,
            'firstname', firstname,
            'lastname', lastname,
            'email', email
        )
    ),
    ']'
) FROM lime_participants;
" 2>/dev/null || echo "[]")

# Handle empty result
if [ "$PARTICIPANTS_JSON" == "NULL" ] || [ -z "$PARTICIPANTS_JSON" ]; then
    PARTICIPANTS_JSON="[]"
fi

# 3. Query Custom Attributes Definitions
echo "Querying attribute definitions..."
ATTRIBUTES_JSON=$(docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "
SELECT CONCAT(
    '[',
    GROUP_CONCAT(
        JSON_OBJECT(
            'attribute_id', attribute_id,
            'defaultname', defaultname,
            'attribute_type', attribute_type
        )
    ),
    ']'
) FROM lime_participant_attribute_names;
" 2>/dev/null || echo "[]")

if [ "$ATTRIBUTES_JSON" == "NULL" ] || [ -z "$ATTRIBUTES_JSON" ]; then
    ATTRIBUTES_JSON="[]"
fi

# 4. Query Attribute Values
# We join attribute values with attribute names to get a clear picture
echo "Querying attribute values..."
VALUES_JSON=$(docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "
SELECT CONCAT(
    '[',
    GROUP_CONCAT(
        JSON_OBJECT(
            'participant_id', pa.participant_id,
            'attribute_name', pan.defaultname,
            'value', pa.value
        )
    ),
    ']'
) 
FROM lime_participant_attribute pa
JOIN lime_participant_attribute_names pan ON pa.attribute_id = pan.attribute_id;
" 2>/dev/null || echo "[]")

if [ "$VALUES_JSON" == "NULL" ] || [ -z "$VALUES_JSON" ]; then
    VALUES_JSON="[]"
fi

# 5. Query Survey Links (Participants shared with survey)
# We check the survey specific token table as that's the ultimate proof of sharing
SURVEY_TOKENS_JSON="[]"
if [ -n "$SID" ]; then
    echo "Querying tokens for survey $SID..."
    # Check if table exists first
    TABLE_EXISTS=$(limesurvey_query "SHOW TABLES LIKE 'lime_tokens_$SID'")
    if [ -n "$TABLE_EXISTS" ]; then
        SURVEY_TOKENS_JSON=$(docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "
        SELECT CONCAT(
            '[',
            GROUP_CONCAT(
                JSON_OBJECT(
                    'email', email,
                    'token', token
                )
            ),
            ']'
        ) FROM lime_tokens_$SID;
        " 2>/dev/null || echo "[]")
    fi
fi

if [ "$SURVEY_TOKENS_JSON" == "NULL" ] || [ -z "$SURVEY_TOKENS_JSON" ]; then
    SURVEY_TOKENS_JSON="[]"
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Combine into one JSON
cat > /tmp/cpdb_result.json << EOF
{
    "survey_id": "$SID",
    "participants": $PARTICIPANTS_JSON,
    "attributes": $ATTRIBUTES_JSON,
    "attribute_values": $VALUES_JSON,
    "survey_tokens": $SURVEY_TOKENS_JSON,
    "timestamp": $(date +%s)
}
EOF

echo "Export complete. Result saved to /tmp/cpdb_result.json"