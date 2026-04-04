#!/bin/bash
echo "=== Setting up Token Custom Attributes Task ==="

source /workspace/scripts/task_utils.sh

# Function to execute SQL via Docker
db_query() {
    docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
}

# Wait for LimeSurvey readiness
wait_for_page_load 5

# Clean up any existing surveys with similar names to prevent ambiguity
echo "Cleaning up previous surveys..."
IDS_TO_DELETE=$(db_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid = ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%post-purchase%satisfaction%'")

for SID in $IDS_TO_DELETE; do
    echo "Deleting old survey SID: $SID"
    # Drop token table if exists
    db_query "DROP TABLE IF EXISTS lime_tokens_$SID"
    # Delete from surveys table (cascades usually, but being safe)
    db_query "DELETE FROM lime_surveys WHERE sid=$SID"
    db_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID"
done

# Record start time
date +%s > /tmp/task_start_time.txt

# Initial survey count
INITIAL_COUNT=$(db_query "SELECT COUNT(*) FROM lime_surveys" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_survey_count.txt

# Ensure Firefox is running and focused
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="