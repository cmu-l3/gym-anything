#!/bin/bash
echo "=== Exporting customize_contacts_list_view results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# 1. Check if the custom listviewdefs.php was created
CUSTOM_FILE="/var/www/html/custom/modules/Contacts/metadata/listviewdefs.php"
FILE_EXISTS=$(docker exec suitecrm-app test -f "$CUSTOM_FILE" && echo "true" || echo "false")
echo "Custom layout file created: $FILE_EXISTS"

# 2. Extract the layout array directly via PHP into JSON format
LAYOUT_JSON="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    LAYOUT_JSON=$(docker exec suitecrm-app php -r "
        @include '$CUSTOM_FILE';
        if(isset(\$listViewDefs['Contacts'])) {
            echo json_encode(\$listViewDefs['Contacts']);
        } else {
            echo '{}';
        }
    " 2>/dev/null || echo "{}")
fi

# 3. Check Apache logs to prove the agent used the Studio UI (Save & Deploy button)
START_LINE=$(cat /tmp/apache_log_start_line.txt 2>/dev/null || echo "0")
STUDIO_USED_COUNT=$(docker exec suitecrm-app tail -n +$((START_LINE + 1)) /var/log/apache2/access.log | grep -c "action=SaveListView" 2>/dev/null || echo "0")
echo "Studio UI 'Save & Deploy' requests: $STUDIO_USED_COUNT"

# 4. Compile results into JSON
RESULT_JSON=$(cat << JSONEOF
{
  "custom_file_exists": ${FILE_EXISTS},
  "layout_defs": ${LAYOUT_JSON},
  "studio_save_requests": ${STUDIO_USED_COUNT},
  "timestamp": "$(date -Iseconds)"
}
JSONEOF
)

# Safely write the results
safe_write_result "/tmp/customize_contacts_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/customize_contacts_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="