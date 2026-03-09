#!/bin/bash
# Export script for manage_customer_accounts task
echo "=== Exporting manage_customer_accounts Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

# 1. Check mikewilson status
echo "Checking mikewilson..."
MIKE_DATA=$(drupal_db_query "SELECT uid, status FROM users_field_data WHERE name='mikewilson'")
MIKE_UID=$(echo "$MIKE_DATA" | awk '{print $1}')
MIKE_STATUS=$(echo "$MIKE_DATA" | awk '{print $2}')

# 2. Check janesmith email
echo "Checking janesmith..."
JANE_DATA=$(drupal_db_query "SELECT uid, mail FROM users_field_data WHERE name='janesmith'")
JANE_UID=$(echo "$JANE_DATA" | awk '{print $1}')
JANE_MAIL=$(echo "$JANE_DATA" | awk '{print $2}')

# 3. Check sarahjohnson existence and details
echo "Checking sarahjohnson..."
SARAH_DATA=$(drupal_db_query "SELECT uid, mail, status, created FROM users_field_data WHERE name='sarahjohnson'")
SARAH_FOUND="false"
SARAH_UID=""
SARAH_MAIL=""
SARAH_STATUS=""
SARAH_CREATED=""
SARAH_PROFILE_FOUND="false"
SARAH_ADDRESS_CITY=""
SARAH_ADDRESS_STATE=""
SARAH_ADDRESS_LINE=""

if [ -n "$SARAH_DATA" ]; then
    SARAH_FOUND="true"
    SARAH_UID=$(echo "$SARAH_DATA" | cut -f1)
    SARAH_MAIL=$(echo "$SARAH_DATA" | cut -f2)
    SARAH_STATUS=$(echo "$SARAH_DATA" | cut -f3)
    SARAH_CREATED=$(echo "$SARAH_DATA" | cut -f4)

    # Check for profile
    # Join profile table with profile__address
    # Note: Address table name depends on field name, usually profile__address
    ADDRESS_DATA=$(drupal_db_query "SELECT pa.address_locality, pa.address_administrative_area, pa.address_line1 FROM profile p JOIN profile__address pa ON p.profile_id = pa.entity_id WHERE p.uid = $SARAH_UID ORDER BY p.profile_id DESC LIMIT 1")
    
    if [ -n "$ADDRESS_DATA" ]; then
        SARAH_PROFILE_FOUND="true"
        SARAH_ADDRESS_CITY=$(echo "$ADDRESS_DATA" | cut -f1)
        SARAH_ADDRESS_STATE=$(echo "$ADDRESS_DATA" | cut -f2)
        SARAH_ADDRESS_LINE=$(echo "$ADDRESS_DATA" | cut -f3)
    fi
fi

# Task Start Time for verification
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Construct JSON
cat > /tmp/manage_customer_accounts_result.json << EOF
{
    "task_start_ts": $TASK_START,
    "mikewilson": {
        "uid": "${MIKE_UID:-}",
        "status": "${MIKE_STATUS:-}"
    },
    "janesmith": {
        "uid": "${JANE_UID:-}",
        "mail": "${JANE_MAIL:-}"
    },
    "sarahjohnson": {
        "found": $SARAH_FOUND,
        "uid": "${SARAH_UID:-}",
        "mail": "${SARAH_MAIL:-}",
        "status": "${SARAH_STATUS:-}",
        "created_ts": "${SARAH_CREATED:-0}",
        "profile_found": $SARAH_PROFILE_FOUND,
        "address_city": "${SARAH_ADDRESS_CITY:-}",
        "address_state": "${SARAH_ADDRESS_STATE:-}",
        "address_line": "${SARAH_ADDRESS_LINE:-}"
    }
}
EOF

# Safe copy to accessible location
cp /tmp/manage_customer_accounts_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete:"
cat /tmp/task_result.json