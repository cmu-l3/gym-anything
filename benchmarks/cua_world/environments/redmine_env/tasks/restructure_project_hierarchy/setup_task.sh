#!/bin/bash
set -e
echo "=== Setting up restructure_project_hierarchy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is ready
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable"
  exit 1
fi

# Get Admin API Key
API_KEY=$(redmine_admin_api_key)
if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
    echo "ERROR: Could not retrieve Admin API Key"
    exit 1
fi

# Function to ensure a project exists via API
ensure_project() {
    local name="$1"
    local identifier="$2"
    local description="$3"
    
    # Check if exists
    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "X-Redmine-API-Key: $API_KEY" \
        "$REDMINE_BASE_URL/projects/$identifier.json")

    if [ "$status_code" != "200" ]; then
        echo "Creating project: $name ($identifier)..."
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -H "X-Redmine-API-Key: $API_KEY" \
            -d "{\"project\": {\"name\": \"$name\", \"identifier\": \"$identifier\", \"description\": \"$description\"}}" \
            "$REDMINE_BASE_URL/projects.json" > /dev/null
    else
        echo "Project $name ($identifier) already exists. Resetting parent to null (top-level)..."
        # Reset parent to null in case it was already moved in a previous run
        # Note: Redmine API might require parent_id: "" or null, usually omitting it or sending null works
        # Using XML or JSON to update
        curl -s -X PUT \
            -H "Content-Type: application/json" \
            -H "X-Redmine-API-Key: $API_KEY" \
            -d '{"project": {"parent_id": null}}' \
            "$REDMINE_BASE_URL/projects/$identifier.json" > /dev/null
    fi
}

# 1. Create Target Parent Project
ensure_project "Mars Rover 2030" "mars-rover-2030" "Main program container for the 2030 mission."

# 2. Create Child Projects (currently independent)
ensure_project "Chassis Design" "chassis-design" "Structural engineering for the rover body."
ensure_project "Power Systems" "power-systems" "Solar arrays and battery management."
ensure_project "Navigation Software" "navigation-software" "Autonomous pathfinding and obstacle avoidance."

# 3. Record Initial IDs (for anti-gaming verification)
echo "Recording initial project IDs..."
# We fetch the list of projects and filter for our specific ones
curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/projects.json?limit=100" > /tmp/all_projects.json

jq -n \
  --argjson projects "$(cat /tmp/all_projects.json)" \
  '{
    mars_rover: ($projects.projects[] | select(.identifier=="mars-rover-2030") | .id),
    chassis: ($projects.projects[] | select(.identifier=="chassis-design") | .id),
    power: ($projects.projects[] | select(.identifier=="power-systems") | .id),
    navigation: ($projects.projects[] | select(.identifier=="navigation-software") | .id)
  }' > /tmp/initial_project_state.json

echo "Initial State:"
cat /tmp/initial_project_state.json

# 4. Launch Firefox and Login
log "Launching Firefox and logging in..."
ensure_redmine_logged_in "$REDMINE_BASE_URL/projects"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="