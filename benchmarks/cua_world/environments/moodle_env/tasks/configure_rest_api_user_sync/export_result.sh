#!/bin/bash
# Export script for Configure REST API task

echo "=== Exporting REST API Configuration Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"; echo "Result saved to $dest_path"
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check Global Web Services Enabled
WS_ENABLED=$(moodle_query "SELECT value FROM mdl_config WHERE name='enablewebservices'" | tr -d '[:space:]')
WS_ENABLED=${WS_ENABLED:-0}

# 2. Check REST Protocol Enabled
REST_ENABLED=$(moodle_query "SELECT enabled FROM mdl_webservice_protocols WHERE name='rest'" | tr -d '[:space:]')
REST_ENABLED=${REST_ENABLED:-0}

# 3. Check Service User Exists
USER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='sis_integration'" | tr -d '[:space:]')
USER_FOUND="false"
if [ -n "$USER_ID" ]; then
    USER_FOUND="true"
fi

# 4. Check Manager Role Assignment (System Context = 1)
# Role shortname 'manager' usually has id 1, but we join to be sure
IS_MANAGER="false"
if [ -n "$USER_ID" ]; then
    MANAGER_ROLE_CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_role_assignments ra JOIN mdl_role r ON ra.roleid = r.id WHERE ra.userid = $USER_ID AND r.shortname = 'manager' AND ra.contextid = 1" | tr -d '[:space:]')
    if [ "$MANAGER_ROLE_CHECK" -gt 0 ]; then
        IS_MANAGER="true"
    fi
fi

# 5. Check External Service
SERVICE_NAME="SIS User Sync"
SERVICE_DATA=$(moodle_query "SELECT id, enabled, restrictedusers FROM mdl_external_services WHERE name='$SERVICE_NAME' LIMIT 1")
SERVICE_FOUND="false"
SERVICE_ID=""
SERVICE_ENABLED="0"
SERVICE_RESTRICTED="0"

if [ -n "$SERVICE_DATA" ]; then
    SERVICE_FOUND="true"
    SERVICE_ID=$(echo "$SERVICE_DATA" | cut -f1 | tr -d '[:space:]')
    SERVICE_ENABLED=$(echo "$SERVICE_DATA" | cut -f2 | tr -d '[:space:]')
    SERVICE_RESTRICTED=$(echo "$SERVICE_DATA" | cut -f3 | tr -d '[:space:]')
fi

# 6. Check Functions
FUNCTIONS_LIST=""
if [ -n "$SERVICE_ID" ]; then
    FUNCTIONS_LIST=$(moodle_query "SELECT f.name FROM mdl_external_functions f JOIN mdl_external_services_functions esf ON f.name = esf.functionname WHERE esf.externalserviceid = $SERVICE_ID")
fi

# 7. Check Authorized User
IS_AUTHORIZED="false"
if [ -n "$SERVICE_ID" ] && [ -n "$USER_ID" ]; then
    AUTH_CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_external_services_users WHERE externalserviceid = $SERVICE_ID AND userid = $USER_ID" | tr -d '[:space:]')
    if [ "$AUTH_CHECK" -gt 0 ]; then
        IS_AUTHORIZED="true"
    fi
fi

# 8. Check Token
TOKEN_EXISTS="false"
if [ -n "$SERVICE_ID" ] && [ -n "$USER_ID" ]; then
    TOKEN_CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_external_tokens WHERE externalserviceid = $SERVICE_ID AND userid = $USER_ID AND tokentype = 1" | tr -d '[:space:]')
    if [ "$TOKEN_CHECK" -gt 0 ]; then
        TOKEN_EXISTS="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/rest_api_result.XXXXXX.json)
# Using python to write JSON to handle list formatting safely
python3 -c "
import json
import sys

functions_str = '''$FUNCTIONS_LIST'''
functions = [f.strip() for f in functions_str.split('\n') if f.strip()]

data = {
    'ws_enabled': $WS_ENABLED,
    'rest_enabled': $REST_ENABLED,
    'user_found': $USER_FOUND,
    'is_manager': $IS_MANAGER,
    'service_found': $SERVICE_FOUND,
    'service_enabled': $SERVICE_ENABLED,
    'service_restricted': $SERVICE_RESTRICTED,
    'functions': functions,
    'is_authorized': $IS_AUTHORIZED,
    'token_exists': $TOKEN_EXISTS,
    'export_timestamp': '$(date -Iseconds)'
}

print(json.dumps(data))
" > "$TEMP_JSON"

safe_write_json "$TEMP_JSON" /tmp/configure_rest_api_user_sync_result.json

echo ""
cat /tmp/configure_rest_api_user_sync_result.json
echo ""
echo "=== Export Complete ==="