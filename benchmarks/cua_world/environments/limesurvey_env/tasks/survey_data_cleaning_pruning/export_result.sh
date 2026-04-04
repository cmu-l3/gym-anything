#!/bin/bash
echo "=== Exporting Survey Data Cleaning Result ==="

source /workspace/scripts/task_utils.sh

# Retrieve SID
if [ ! -f /tmp/task_sid.txt ]; then
    echo "Error: SID not found."
    # Try to recover by looking up title
    SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title='Product Concept Test 2025' LIMIT 1")
    if [ -z "$SID" ]; then
        echo "Could not find survey."
        echo '{"error": "Survey not found"}' > /tmp/task_result.json
        exit 0
    fi
else
    SID=$(cat /tmp/task_sid.txt)
fi

TABLE_NAME="lime_survey_${SID}"

# Get GID and QIDs to construct column names dynamically
# We know the question titles are 'fname' and 'email'
# Structure: {SID}X{GID}X{QID}

# Helper to get column name by question title
get_col_name() {
    local q_title=$1
    limesurvey_query "
        SELECT CONCAT(s.sid, 'X', g.gid, 'X', q.qid)
        FROM lime_questions q
        JOIN lime_groups g ON q.gid = g.gid
        JOIN lime_surveys s ON g.sid = s.sid
        WHERE s.sid = $SID AND q.title = '$q_title'
        LIMIT 1
    "
}

COL_NAME=$(get_col_name "fname")
COL_EMAIL=$(get_col_name "email")

echo "Mapping: fname -> $COL_NAME, email -> $COL_EMAIL"

# 1. Check if table exists (Survey active)
TABLE_EXISTS=$(limesurvey_query "SHOW TABLES LIKE '$TABLE_NAME'")

if [ -z "$TABLE_EXISTS" ]; then
    echo "Table $TABLE_NAME does not exist (Survey deactivated?)"
    SURVEY_ACTIVE="false"
else
    SURVEY_ACTIVE="true"
fi

# 2. Count remaining Bad Data
# Criteria 1: Incomplete (submitdate IS NULL)
COUNT_INCOMPLETE=$(limesurvey_query "SELECT COUNT(*) FROM $TABLE_NAME WHERE submitdate IS NULL")

# Criteria 2: Name is TEST
COUNT_TEST_NAME=$(limesurvey_query "SELECT COUNT(*) FROM $TABLE_NAME WHERE \`$COL_NAME\` = 'TEST'")

# Criteria 3: Email is @example.com
COUNT_SPAM_EMAIL=$(limesurvey_query "SELECT COUNT(*) FROM $TABLE_NAME WHERE \`$COL_EMAIL\` LIKE '%@example.com'")

# 3. Check Good Data Preservation
# Jane Doe
PRESERVED_JANE=$(limesurvey_query "SELECT COUNT(*) FROM $TABLE_NAME WHERE \`$COL_NAME\` = 'Jane Doe' AND submitdate IS NOT NULL")

# Marcus Smith
PRESERVED_MARCUS=$(limesurvey_query "SELECT COUNT(*) FROM $TABLE_NAME WHERE \`$COL_NAME\` = 'Marcus Smith' AND submitdate IS NOT NULL")

# Li Wei
PRESERVED_LI=$(limesurvey_query "SELECT COUNT(*) FROM $TABLE_NAME WHERE \`$COL_NAME\` = 'Li Wei' AND submitdate IS NOT NULL")

# 4. Total Count
TOTAL_REMAINING=$(limesurvey_query "SELECT COUNT(*) FROM $TABLE_NAME")

# Final Screenshot
take_screenshot /tmp/task_final.png

# Build JSON
cat > /tmp/task_result_temp.json << EOF
{
    "survey_active": $SURVEY_ACTIVE,
    "table_name": "$TABLE_NAME",
    "bad_data_counts": {
        "incomplete": ${COUNT_INCOMPLETE:-0},
        "test_name": ${COUNT_TEST_NAME:-0},
        "spam_email": ${COUNT_SPAM_EMAIL:-0}
    },
    "good_data_preserved": {
        "Jane_Doe": ${PRESERVED_JANE:-0},
        "Marcus_Smith": ${PRESERVED_MARCUS:-0},
        "Li_Wei": ${PRESERVED_LI:-0}
    },
    "total_remaining": ${TOTAL_REMAINING:-0}
}
EOF

# Move with permission fix
sudo mv /tmp/task_result_temp.json /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Export completed."
cat /tmp/task_result.json