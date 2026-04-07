#!/bin/bash
echo "=== Setting up provision_cleaning_crew_access task ==="
source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

wait_for_ac_demo
ac_login

# Clean up any pre-existing data that might conflict
echo "Cleaning up pre-existing test data..."

# Time Profiles
TP_IDS=$(ac_api GET "/timeProfiles" | jq -r '.[] | select(.name=="Overnight Cleaning") | .id' 2>/dev/null)
for id in $TP_IDS; do ac_api DELETE "/timeProfiles/$id" > /dev/null 2>&1; done
TP_IDS=$(ac_api GET "/time-profiles" | jq -r '.[] | select(.name=="Overnight Cleaning") | .id' 2>/dev/null)
for id in $TP_IDS; do ac_api DELETE "/time-profiles/$id" > /dev/null 2>&1; done

# Users
U_IDS=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Elena" and .lastName=="Rostova") | .id' 2>/dev/null)
for id in $U_IDS; do ac_api DELETE "/users/$id" > /dev/null 2>&1; done

U_IDS=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Mateo" and .lastName=="Cruz") | .id' 2>/dev/null)
for id in $U_IDS; do ac_api DELETE "/users/$id" > /dev/null 2>&1; done

# Groups
G_IDS=$(ac_api GET "/groups" | jq -r '.[] | select(.name=="Cleaning Crew") | .id' 2>/dev/null)
for id in $G_IDS; do ac_api DELETE "/groups/$id" > /dev/null 2>&1; done

# Delete text file
rm -f /home/ga/Documents/cleaning_crew_setup.txt

# Launch Firefox
launch_firefox_to "${AC_URL}/" 8

take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="