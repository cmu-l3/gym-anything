#!/bin/bash
# Export script for fix_store_issues task
# Queries database to check if the 4 issues are resolved

echo "=== Exporting fix_store_issues Result ==="

. /workspace/scripts/task_utils.sh

# Fallback definition
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Product Status
# We check by Title. Status 1 = Published, 0 = Unpublished
PRODUCT_STATUS=$(drupal_db_query "SELECT status FROM commerce_product_field_data WHERE title LIKE '%Samsung Galaxy S24 Ultra%' LIMIT 1")
PRODUCT_STATUS=${PRODUCT_STATUS:-0}

# 2. Check Store Email
STORE_EMAIL=$(drupal_db_query "SELECT mail FROM commerce_store_field_data WHERE name = 'Urban Electronics' LIMIT 1")
STORE_EMAIL=${STORE_EMAIL:-""}

# 3. Check Promotion End Date
# Format from DB is usually 'Y-m-d' or 'Y-m-dTH:i:s'
PROMO_END_DATE=$(drupal_db_query "SELECT end_date FROM commerce_promotion_field_data WHERE name LIKE '%Electronics 15% Off%' LIMIT 1")
PROMO_END_DATE=${PROMO_END_DATE:-""}

# 4. Check User Status
# Status 1 = Active, 0 = Blocked
USER_STATUS=$(drupal_db_query "SELECT status FROM users_field_data WHERE name = 'mikewilson' LIMIT 1")
USER_STATUS=${USER_STATUS:-0}

# Get modification timestamps to verify work done during task
# (Simple check: we assume if values match target, work was done, 
# since setup script explicitly set them to wrong values)

# Create JSON Result
cat > /tmp/fix_store_issues_result.json << EOF
{
    "product_status": $PRODUCT_STATUS,
    "store_email": "$(echo "$STORE_EMAIL" | tr -d '\n\r')",
    "promo_end_date": "$(echo "$PROMO_END_DATE" | tr -d '\n\r')",
    "user_status": $USER_STATUS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Secure permissions
chmod 666 /tmp/fix_store_issues_result.json 2>/dev/null || true

echo "Exported Result:"
cat /tmp/fix_store_issues_result.json

echo "=== Export Complete ==="