#!/bin/bash
echo "=== Setting up create_time_profile task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# Clean up prior 'Weekend Access' time profile
EXISTING=$(ac_api GET "/timeProfiles" | jq -r '.[] | select(.name=="Weekend Access") | .id' 2>/dev/null)
for tid in $EXISTING; do
    ac_api DELETE "/timeProfiles/$tid" > /dev/null 2>&1 && echo "Deleted prior Weekend Access profile" || true
done

# Navigate to Time Profiles page
launch_firefox_to "${AC_URL}/#/timeProfiles" 8

take_screenshot /tmp/task_create_time_profile_start.png
echo "=== Task create_time_profile setup complete ==="
