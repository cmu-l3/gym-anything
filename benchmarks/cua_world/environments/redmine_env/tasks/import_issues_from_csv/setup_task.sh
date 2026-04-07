#!/bin/bash
set -e
echo "=== Setting up import_issues_from_csv task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Prepare the CSV file with realistic data
mkdir -p /home/ga/Documents
CSV_FILE="/home/ga/Documents/facility_tasks.csv"

# Current year for valid dates
YR=$(date +%Y)

cat > "$CSV_FILE" <<EOF
tracker,subject,description,priority,start_date,due_date,estimated_hours
Bug,HVAC System Replacement - Building A Wing 3,Complete replacement of failing HVAC unit.,High,$YR-01-10,$YR-02-20,320
Feature,Access Control System Upgrade,Upgrade card readers to support NFC.,Normal,$YR-03-01,$YR-04-15,480
Bug,Roof Leak Repair - Parking Structure Level 3,Emergency patch for severe leak.,Urgent,$YR-05-05,$YR-05-10,160
Feature,LED Lighting Retrofit - Office Floors 4-8,Replace fluorescent fixtures with LED.,Normal,$YR-06-01,$YR-08-30,540
Support,Fire Suppression System Annual Inspection,Mandatory annual compliance check.,High,$YR-09-01,$YR-09-07,80
Bug,Elevator Modernization - Units 3 and 4,Controller upgrade for efficiency.,High,$YR-10-01,$YR-12-15,720
Feature,EV Charging Station Installation,Install 10 Level 2 chargers in visitor lot.,Normal,$YR-02-15,$YR-03-30,280
Support,Landscaping Contract Renewal and Redesign,Review bids for 2025 season.,Low,$YR-11-01,$YR-11-15,40
EOF

chown ga:ga "$CSV_FILE"
echo "Created CSV file at $CSV_FILE"

# 3. Ensure Redmine is reachable
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# 4. Create the 'Oakwood Facilities' project if it doesn't exist
# We use curl with Basic Auth (admin:Admin1234!)
PROJECT_ID="oakwood-facilities"
PROJECT_NAME="Oakwood Facilities"

echo "Checking if project '$PROJECT_ID' exists..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u admin:Admin1234! \
  "$REDMINE_BASE_URL/projects/$PROJECT_ID.json")

if [ "$HTTP_CODE" != "200" ]; then
  echo "Creating project '$PROJECT_NAME'..."
  curl -s -o /dev/null -X POST -u admin:Admin1234! \
    -H "Content-Type: application/json" \
    -d "{\"project\":{\"name\":\"$PROJECT_NAME\",\"identifier\":\"$PROJECT_ID\",\"enabled_module_names\":[\"issue_tracking\"]}}" \
    "$REDMINE_BASE_URL/projects.json"
  echo "Project created."
else
  echo "Project already exists. Cleaning up existing issues..."
  # Just in case, delete existing issues to ensure clean state
  # Getting IDs
  ISSUE_IDS=$(curl -s -u admin:Admin1234! "$REDMINE_BASE_URL/projects/$PROJECT_ID/issues.json?status_id=*" | jq -r '.issues[].id')
  for id in $ISSUE_IDS; do
    curl -s -X DELETE -u admin:Admin1234! "$REDMINE_BASE_URL/issues/$id.json"
  done
  echo "Cleaned existing issues."
fi

# 5. Record initial issue count (should be 0)
INITIAL_COUNT=$(curl -s -u admin:Admin1234! "$REDMINE_BASE_URL/projects/$PROJECT_ID/issues.json?status_id=*" | jq '.total_count')
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial issue count: $INITIAL_COUNT"

# 6. Log in and navigate to the project issues page
TARGET_URL="$REDMINE_BASE_URL/projects/$PROJECT_ID/issues"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

focus_firefox || true
sleep 2

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png
log "Task start screenshot: /tmp/task_initial.png"

echo "=== Task setup complete ==="