#!/bin/bash
echo "=== Exporting customize_user_profile_fields results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get API Key for Admin to query data
API_KEY=$(redmine_admin_api_key)

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
    echo "WARNING: Could not retrieve Admin API key. Using basic auth fallback or failing."
    # Attempt to fetch via docker exec if seed file missing
    API_KEY=$(docker exec redmine bundle exec rails runner "puts User.find_by(login: 'admin').api_key" 2>/dev/null || echo "")
fi

echo "Fetching validation data from Redmine API..."

# 1. Fetch Custom Fields
# We filter for user custom fields. Since the API list returns all, we'll fetch all and filter in jq/python.
curl -s -H "X-Redmine-API-Key: $API_KEY" \
     "$REDMINE_BASE_URL/custom_fields.json" > /tmp/custom_fields_raw.json

# 2. Fetch Admin User details (including custom values)
# We need to include custom_fields in the response
curl -s -H "X-Redmine-API-Key: $API_KEY" \
     "$REDMINE_BASE_URL/users/1.json?include=custom_fields" > /tmp/user_admin_raw.json

# 3. Compile into a single result JSON
# We use jq to construct a clean result object.
# Note: Custom fields in the API response contain regex, possible_values, etc.

jq -n \
  --slurpfile fields /tmp/custom_fields_raw.json \
  --slurpfile user /tmp/user_admin_raw.json \
  --arg start_time "$TASK_START" \
  --arg end_time "$TASK_END" \
  '{
    task_start: $start_time,
    task_end: $end_time,
    custom_fields: $fields[0].custom_fields,
    admin_user: $user[0].user
  }' > /tmp/task_result_temp.json

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result summary:"
jq '{field_count: (.custom_fields | length), user_login: .admin_user.login}' /tmp/task_result.json

echo "=== Export complete ==="