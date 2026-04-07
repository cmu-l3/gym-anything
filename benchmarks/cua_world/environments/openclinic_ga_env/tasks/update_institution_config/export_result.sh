#!/bin/bash
# Export script for update_institution_config task
# Queries the database for configuration parameters and exports to JSON

echo "=== Exporting Update Institution Config Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# ------------------------------------------------------------------
# Strategy: Search the database for the expected strings
# ------------------------------------------------------------------
# Since the exact table/column names for institution config can vary 
# across versions or be stored in generic property tables, we search 
# for the specific values the agent was asked to enter.

EXPECTED_NAME="Saint Helena Regional Medical Center"
EXPECTED_ADDRESS="450 Commonwealth Boulevard, Richmond, VA 23219"
EXPECTED_PHONE="+1-804-555-0142"
EXPECTED_FAX="+1-804-555-0143"

echo "Searching database for updated values..."

# Helper function to search a DB for a string
search_db_value() {
    local db="$1"
    local search_term="$2"
    # Search all text columns in the database for the value
    # This is a brute-force approach ensuring we find it regardless of schema specifics
    # We limit to likely tables to save time if needed, but a full search is safer
    
    # Simple check: Is the string present in the specific OC_PARAMETERS table often used?
    local direct_check=$($MYSQL_BIN $MYSQL_OPTS "$db" -N -e "SELECT parameter, value FROM OC_PARAMETERS WHERE value LIKE '%$search_term%' LIMIT 1" 2>/dev/null)
    
    if [ -n "$direct_check" ]; then
        echo "$direct_check"
        return
    fi
    
    # Fallback: Check SystemProps or Config tables if they exist
    local other_tables="SystemProperties AdminConfig OC_CONFIG"
    for t in $other_tables; do
        local check=$($MYSQL_BIN $MYSQL_OPTS "$db" -N -e "SELECT * FROM $t WHERE value LIKE '%$search_term%' LIMIT 1" 2>/dev/null)
        if [ -n "$check" ]; then
            echo "$db.$t: $check"
            return
        fi
    done
}

# Search for Name
FOUND_NAME_OCADMIN=$(search_db_value "ocadmin_dbo" "Saint Helena")
FOUND_NAME_OPENCLINIC=$(search_db_value "openclinic_dbo" "Saint Helena")

# Search for Address
FOUND_ADDRESS_OCADMIN=$(search_db_value "ocadmin_dbo" "450 Commonwealth")
FOUND_ADDRESS_OPENCLINIC=$(search_db_value "openclinic_dbo" "450 Commonwealth")

# Search for Phone (try exact and stripped)
FOUND_PHONE_OCADMIN=$(search_db_value "ocadmin_dbo" "804-555-0142")
if [ -z "$FOUND_PHONE_OCADMIN" ]; then
    FOUND_PHONE_OCADMIN=$(search_db_value "ocadmin_dbo" "8045550142")
fi

# Search for Fax
FOUND_FAX_OCADMIN=$(search_db_value "ocadmin_dbo" "804-555-0143")

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
# We escape the found values to ensure valid JSON
TEMP_JSON=$(mktemp /tmp/config_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found_name_ocadmin": "$(echo $FOUND_NAME_OCADMIN | sed 's/"/\\"/g')",
    "found_name_openclinic": "$(echo $FOUND_NAME_OPENCLINIC | sed 's/"/\\"/g')",
    "found_address_ocadmin": "$(echo $FOUND_ADDRESS_OCADMIN | sed 's/"/\\"/g')",
    "found_address_openclinic": "$(echo $FOUND_ADDRESS_OPENCLINIC | sed 's/"/\\"/g')",
    "found_phone": "$(echo $FOUND_PHONE_OCADMIN | sed 's/"/\\"/g')",
    "found_fax": "$(echo $FOUND_FAX_OCADMIN | sed 's/"/\\"/g')",
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json