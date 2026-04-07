#!/bin/bash
# Export script for bulk_import_intranet_users task

echo "=== Exporting bulk_import_intranet_users result ==="

source /workspace/scripts/task_utils.sh
cd /var/www/html/wordpress

take_screenshot /tmp/task_final.png

# ============================================================
# Gather Role Information
# ============================================================
EMPLOYEE_ROLE_EXISTS="false"
EMPLOYEE_CAPS="{}"
if wp role exists employee --allow-root; then
    EMPLOYEE_ROLE_EXISTS="true"
    # Get JSON string of capabilities, e.g., {"read":true,"read_private_posts":true}
    EMPLOYEE_CAPS=$(wp role get employee --fields=capabilities --format=json --allow-root 2>/dev/null || echo "{}")
fi

SUBSCRIBER_ROLE_EXISTS="false"
if wp role exists subscriber --allow-root; then
    SUBSCRIBER_ROLE_EXISTS="true"
fi

# ============================================================
# Gather User Counts
# ============================================================
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")
TOTAL_USER_COUNT=$(wp user list --format=count --allow-root)
EMPLOYEE_USER_COUNT=$(wp user list --role=employee --format=count --allow-root 2>/dev/null || echo "0")

# ============================================================
# Spot Check Target Users
# ============================================================
check_user() {
    local username="$1"
    local found="false"
    local email=""
    local first_name=""
    local last_name=""
    local department=""
    local registered=""

    if wp user get "$username" --format=json --allow-root > /dev/null 2>&1; then
        found="true"
        email=$(wp user get "$username" --field=user_email --allow-root | sed 's/"/\\"/g' | tr -d '\n')
        first_name=$(wp user get "$username" --field=first_name --allow-root | sed 's/"/\\"/g' | tr -d '\n')
        last_name=$(wp user get "$username" --field=last_name --allow-root | sed 's/"/\\"/g' | tr -d '\n')
        department=$(wp user meta get "$username" department --allow-root 2>/dev/null | sed 's/"/\\"/g' | tr -d '\n')
        registered=$(wp user get "$username" --field=user_registered --allow-root | sed 's/"/\\"/g' | tr -d '\n')
    fi

    echo "{\"found\": $found, \"email\": \"$email\", \"first_name\": \"$first_name\", \"last_name\": \"$last_name\", \"department\": \"$department\", \"registered\": \"$registered\"}"
}

USER_ASMITH=$(check_user "asmith")
USER_EWILLIAMS=$(check_user "ewilliams")
USER_YRODRIGUEZ=$(check_user "yrodriguez")

# ============================================================
# Export JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "roles": {
        "employee_exists": $EMPLOYEE_ROLE_EXISTS,
        "employee_caps": $EMPLOYEE_CAPS,
        "subscriber_exists": $SUBSCRIBER_ROLE_EXISTS
    },
    "counts": {
        "initial_total": $INITIAL_USER_COUNT,
        "current_total": $TOTAL_USER_COUNT,
        "employee_count": $EMPLOYEE_USER_COUNT
    },
    "spot_checks": {
        "asmith": $USER_ASMITH,
        "ewilliams": $USER_EWILLIAMS,
        "yrodriguez": $USER_YRODRIGUEZ
    },
    "task_start_timestamp": $(cat /tmp/task_start_timestamp 2>/dev/null || echo "0"),
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/bulk_import_result.json 2>/dev/null || sudo rm -f /tmp/bulk_import_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/bulk_import_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/bulk_import_result.json
chmod 666 /tmp/bulk_import_result.json 2>/dev/null || sudo chmod 666 /tmp/bulk_import_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export completed successfully:"
cat /tmp/bulk_import_result.json