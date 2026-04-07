#!/bin/bash
echo "=== Exporting Bulk Password Reset Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the database to check 'auth_forcepasswordchange' preference for our relevant users
# We join mdl_user with mdl_user_preferences
# Note: users without the preference set will return NULL for value, which we treat as 0

echo "Querying user status..."

# Define the users we care about
USERS_LIST="'liam.smith','olivia.tremblay','noah.gauthier','james.johnson','emma.williams','charlie.brown'"

QUERY="
SELECT 
    u.username, 
    u.country, 
    COALESCE(up.value, 0) as force_change 
FROM mdl_user u 
LEFT JOIN mdl_user_preferences up 
    ON u.id = up.userid AND up.name = 'auth_forcepasswordchange' 
WHERE u.username IN ($USERS_LIST)
ORDER BY u.country, u.username;
"

# Execute query using the utility function (handles Docker vs Native auto-detection)
# We use moodle_query which outputs tab-separated values without headers
RESULTS=$(moodle_query "$QUERY")

echo "Database results:"
echo "$RESULTS"

# Create a structured JSON output
# We will parse the tab-separated output into a JSON array

TEMP_JSON=$(mktemp /tmp/reset_result.XXXXXX.json)

# Start JSON object
echo "{" > "$TEMP_JSON"
echo "  \"users\": [" >> "$TEMP_JSON"

# Process each line
FIRST=1
while IFS=$'\t' read -r username country force_change; do
    if [ "$FIRST" -eq 1 ]; then
        FIRST=0
    else
        echo "," >> "$TEMP_JSON"
    fi
    
    # Handle potentially empty values
    country=${country:-""}
    force_change=${force_change:-0}
    
    cat >> "$TEMP_JSON" << ENTRY
    {
      "username": "$username",
      "country": "$country",
      "force_change": "$force_change"
    }
ENTRY
done <<< "$RESULTS"

echo "  ]," >> "$TEMP_JSON"
echo "  \"export_timestamp\": \"$(date -Iseconds)\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Save to final location
safe_write_json "$TEMP_JSON" /tmp/bulk_password_reset_result.json

echo ""
echo "Exported JSON:"
cat /tmp/bulk_password_reset_result.json
echo ""
echo "=== Export Complete ==="