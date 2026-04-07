#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up package_release_milestone task ==="

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Redmine
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# 3. Provision Data via API using Admin credentials
# We use Basic Auth (admin:Admin1234!) for simplicity
API_CRED="admin:Admin1234!"
BASE_API="$REDMINE_BASE_URL"
PROJECT_ID="atlantic-horizon"

echo "Provisioning project data..."

# Create Project
curl -s -X POST -u "$API_CRED" \
  -H "Content-Type: application/json" \
  -d '{"project": {"name": "Atlantic Horizon", "identifier": "'"$PROJECT_ID"'", "description": "Offshore wind farm development project."}}' \
  "$BASE_API/projects.json" > /dev/null

# Enable Wiki module (sometimes needs explicit enable, though usually default)
# We can't easily toggle modules via API v1, assuming default modules include Issue Tracking and Wiki.

# Create "Survey Phase 1" Version (Distractor)
curl -s -X POST -u "$API_CRED" \
  -H "Content-Type: application/json" \
  -d '{"version": {"name": "Survey Phase 1", "status": "closed"}}' \
  "$BASE_API/projects/$PROJECT_ID/versions.json" > /dev/null

# Get IDs for priorities and statuses
# We assume standard IDs from default load: 
# Statuses: New(1), In Progress(2), Resolved(3), Feedback(4), Closed(5), Rejected(6)
# Trackers: Bug(1), Feature(2), Support(3)

# Helper to create issue
create_issue() {
  local subject="$1"
  local status_id="$2"
  local version_id="$3" # Optional, pass "" if none
  
  local json="{\"issue\": {\"project_id\": \"$PROJECT_ID\", \"subject\": \"$subject\", \"status_id\": $status_id, \"priority_id\": 2, \"tracker_id\": 2}}"
  
  if [ -n "$version_id" ]; then
    # We need to fetch the version ID by name first or just pass the name if API allows? 
    # API usually requires ID. Let's fetch IDs first.
    :
  else
    # Just create without version
    curl -s -X POST -u "$API_CRED" \
      -H "Content-Type: application/json" \
      -d "$json" \
      "$BASE_API/issues.json" > /dev/null
  fi
}

# Fetch Version ID for "Survey Phase 1"
VERSION_JSON=$(curl -s -u "$API_CRED" "$BASE_API/projects/$PROJECT_ID/versions.json")
SURVEY_VER_ID=$(echo "$VERSION_JSON" | jq -r '.versions[] | select(.name=="Survey Phase 1") | .id')

# Create Issues

# Group A: Target (Resolved/Closed, No Version)
# Status: Resolved (3) or Closed (5)
curl -s -X POST -u "$API_CRED" -H "Content-Type: application/json" \
  -d "{\"issue\": {\"project_id\": \"$PROJECT_ID\", \"subject\": \"Submit EPA Environmental Impact Statement\", \"status_id\": 5}}" \
  "$BASE_API/issues.json" > /dev/null

curl -s -X POST -u "$API_CRED" -H "Content-Type: application/json" \
  -d "{\"issue\": {\"project_id\": \"$PROJECT_ID\", \"subject\": \"Marine Mammal Acoustic Survey Report\", \"status_id\": 3}}" \
  "$BASE_API/issues.json" > /dev/null

curl -s -X POST -u "$API_CRED" -H "Content-Type: application/json" \
  -d "{\"issue\": {\"project_id\": \"$PROJECT_ID\", \"subject\": \"Coastal Zone Management Consistency Certification\", \"status_id\": 3}}" \
  "$BASE_API/issues.json" > /dev/null

curl -s -X POST -u "$API_CRED" -H "Content-Type: application/json" \
  -d "{\"issue\": {\"project_id\": \"$PROJECT_ID\", \"subject\": \"FAA Determination of No Hazard\", \"status_id\": 5}}" \
  "$BASE_API/issues.json" > /dev/null

# Group B: Distractor Active (New/In Progress, No Version)
# Status: New (1) or In Progress (2)
curl -s -X POST -u "$API_CRED" -H "Content-Type: application/json" \
  -d "{\"issue\": {\"project_id\": \"$PROJECT_ID\", \"subject\": \"Turbine Supply Agreement Negotiation\", \"status_id\": 2}}" \
  "$BASE_API/issues.json" > /dev/null

curl -s -X POST -u "$API_CRED" -H "Content-Type: application/json" \
  -d "{\"issue\": {\"project_id\": \"$PROJECT_ID\", \"subject\": \"Substation Electrical Design\", \"status_id\": 1}}" \
  "$BASE_API/issues.json" > /dev/null

# Group C: Distractor Versioned (Closed, assigned to Survey Phase 1)
curl -s -X POST -u "$API_CRED" -H "Content-Type: application/json" \
  -d "{\"issue\": {\"project_id\": \"$PROJECT_ID\", \"subject\": \"Geophysical Seabed Survey\", \"status_id\": 5, \"fixed_version_id\": $SURVEY_VER_ID}}" \
  "$BASE_API/issues.json" > /dev/null

curl -s -X POST -u "$API_CRED" -H "Content-Type: application/json" \
  -d "{\"issue\": {\"project_id\": \"$PROJECT_ID\", \"subject\": \"Meteorological Tower Installation\", \"status_id\": 3, \"fixed_version_id\": $SURVEY_VER_ID}}" \
  "$BASE_API/issues.json" > /dev/null

echo "Data provisioning complete."

# 4. Launch Firefox and Login
TARGET_URL="$REDMINE_BASE_URL/projects/$PROJECT_ID"
log "Opening Firefox at: $TARGET_URL"

# Use the helper to handle login and navigation
if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

focus_firefox || true
sleep 2

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png
log "Initial screenshot captured."

echo "=== Setup complete ==="