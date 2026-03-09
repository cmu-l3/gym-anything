#!/bin/bash
echo "=== Exporting Market Research Screener Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Find the Survey ID based on title
SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Streaming%' ORDER BY surveyls_survey_id DESC LIMIT 1" 2>/dev/null)

SURVEY_FOUND="false"
QUESTION_FOUND="false"
QID=""
Q_TYPE=""
Q_MANDATORY=""
Q_OTHER=""
ATTR_RANDOM=""
ATTR_EXCLUSIVE=""
ANSWER_CODES=""

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey ID: $SID"

    # 2. Find the Question (Multiple Choice 'M' in this survey)
    # We look for type 'M' (Multiple choice)
    Q_DATA=$(limesurvey_query "SELECT qid, type, mandatory, other FROM lime_questions WHERE sid=$SID AND type='M' LIMIT 1" 2>/dev/null)
    
    if [ -n "$Q_DATA" ]; then
        QUESTION_FOUND="true"
        QID=$(echo "$Q_DATA" | awk '{print $1}')
        Q_TYPE=$(echo "$Q_DATA" | awk '{print $2}')
        Q_MANDATORY=$(echo "$Q_DATA" | awk '{print $3}')
        Q_OTHER=$(echo "$Q_DATA" | awk '{print $4}')
        
        echo "Found Question ID: $QID, Type: $Q_TYPE"

        # 3. Get Question Attributes (Randomization and Exclusion)
        # Note: Attribute names in DB might differ slightly by version, but usually 'random_order' and 'exclusive_option'
        ATTR_RANDOM=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$QID AND attribute='random_order'" 2>/dev/null)
        ATTR_EXCLUSIVE=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$QID AND attribute='exclusive_option'" 2>/dev/null)

        # 4. Get Answer Codes
        # Group concat codes to check for S01-S05 and NONE
        ANSWER_CODES=$(limesurvey_query "SELECT GROUP_CONCAT(code ORDER BY code SEPARATOR ',') FROM lime_answers WHERE qid=$QID" 2>/dev/null)
    else
        echo "No Multiple Choice question found in survey $SID"
    fi
else
    echo "Survey 'Streaming Media Consumption' not found."
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "question_found": $QUESTION_FOUND,
    "qid": "$QID",
    "type": "$Q_TYPE",
    "mandatory": "$Q_MANDATORY",
    "other_enabled": "$Q_OTHER",
    "attribute_random_order": "$ATTR_RANDOM",
    "attribute_exclusive_option": "$ATTR_EXCLUSIVE",
    "answer_codes": "$ANSWER_CODES",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/market_research_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/market_research_result.json
chmod 666 /tmp/market_research_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/market_research_result.json"
cat /tmp/market_research_result.json
echo "=== Export complete ==="