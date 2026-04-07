#!/bin/bash
set -e

echo "=== Setting up schedule_sequential_routine task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for wger web service to be fully responsive
wait_for_wger_page

# 3. Generate a random end date for the '5x5 Beginner' routine (between 30 and 100 days in the future)
RANDOM_DAYS=$(( ( RANDOM % 70 ) + 30 ))
TARGET_END_DATE=$(date -d "+${RANDOM_DAYS} days" +%Y-%m-%d)

# 4. Inject this random date into the database to prevent the agent from hardcoding a guess
echo "Setting 5x5 Beginner end date to: $TARGET_END_DATE"
db_query "UPDATE manager_routine SET \"end\" = '${TARGET_END_DATE}' WHERE name = '5x5 Beginner'"

# 5. Record the initial state for verification
db_query "SELECT COUNT(*) FROM manager_routine" > /tmp/initial_routine_count.txt
echo "$TARGET_END_DATE" > /tmp/original_end_date.txt

# 6. Make sure no routine already exists with the target name
db_query "DELETE FROM manager_routine WHERE name = 'Intermediate Hypertrophy'"

# 7. Launch Firefox to the wger dashboard
launch_firefox_to "http://localhost/en/dashboard/" 5

# 8. Take initial screenshot
take_screenshot /tmp/task_setup.png

echo "=== Setup complete ==="