#!/bin/bash
echo "=== Exporting restructure_project_hierarchy results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get Admin API Key
API_KEY=$(redmine_admin_api_key)

# Fetch current state of the relevant projects
# We fetch them individually to ensure we get fresh data including parent_id
fetch_project() {
    local identifier="$1"
    curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/projects/$identifier.json"
}

MARS_JSON=$(fetch_project "mars-rover-2030")
CHASSIS_JSON=$(fetch_project "chassis-design")
POWER_JSON=$(fetch_project "power-systems")
NAV_JSON=$(fetch_project "navigation-software")

# Combine into a result JSON
# We include the initial state file content as well
jq -n \
    --argjson mars "$MARS_JSON" \
    --argjson chassis "$CHASSIS_JSON" \
    --argjson power "$POWER_JSON" \
    --argjson nav "$NAV_JSON" \
    --slurpfile initial /tmp/initial_project_state.json \
    '{
        final_state: {
            mars_rover: $mars.project,
            chassis: $chassis.project,
            power: $power.project,
            navigation: $nav.project
        },
        initial_state: $initial[0],
        screenshot_path: "/tmp/task_final.png"
    }' > /tmp/task_result.json

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="