#!/bin/bash
echo "=== Exporting enrich_customer_profile result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load Ground Truth
if [ -f "/tmp/task_data/ground_truth.json" ]; then
    GROUND_TRUTH=$(cat /tmp/task_data/ground_truth.json)
    TARGET_EMAIL=$(echo "$GROUND_TRUTH" | jq -r '.email')
else
    echo "ERROR: Ground truth not found"
    GROUND_TRUTH="{}"
    TARGET_EMAIL=""
fi

# Query Database for Final Customer State
# We need to join customers, emails, and potentially phones/socials
# FreeScout stores phones in 'phones' table or 'phone' column depending on version/plugins
# Standard FreeScout (Laravel) often puts phones in a related table 'phones' linked by customer_id
# or simply in 'phone' column if simplified. We will check both.

echo "Querying database for customer: $TARGET_EMAIL"

# Get Customer ID first
CUST_ID=$(fs_query "SELECT customer_id FROM emails WHERE email = '$TARGET_EMAIL' LIMIT 1" 2>/dev/null)

if [ -n "$CUST_ID" ]; then
    # Get basic info
    CUST_DATA=$(fs_query "SELECT first_name, last_name, job_title, notes, background_info FROM customers WHERE id = $CUST_ID LIMIT 1" 2>/dev/null)
    
    # Get Phone(s)
    # Try 'phones' table first (standard FreeScout schema)
    PHONE_DATA=$(fs_query "SELECT value FROM phones WHERE customer_id = $CUST_ID LIMIT 1" 2>/dev/null)
    
    # Build JSON parts
    DB_FIRST=$(echo "$CUST_DATA" | cut -f1)
    DB_LAST=$(echo "$CUST_DATA" | cut -f2)
    DB_TITLE=$(echo "$CUST_DATA" | cut -f3)
    DB_NOTES=$(echo "$CUST_DATA" | cut -f4)
    DB_BG=$(echo "$CUST_DATA" | cut -f5)
    
    DB_PHONE="$PHONE_DATA"
    
    CUSTOMER_FOUND="true"
else
    CUSTOMER_FOUND="false"
    DB_FIRST=""
    DB_LAST=""
    DB_TITLE=""
    DB_NOTES=""
    DB_BG=""
    DB_PHONE=""
fi

# Escape strings for JSON
DB_FIRST=$(echo "$DB_FIRST" | sed 's/"/\\"/g')
DB_LAST=$(echo "$DB_LAST" | sed 's/"/\\"/g')
DB_TITLE=$(echo "$DB_TITLE" | sed 's/"/\\"/g')
DB_NOTES=$(echo "$DB_NOTES" | sed 's/"/\\"/g' | tr -d '\n')
DB_BG=$(echo "$DB_BG" | sed 's/"/\\"/g' | tr -d '\n')
DB_PHONE=$(echo "$DB_PHONE" | sed 's/"/\\"/g')

# Combine Ground Truth and DB State into Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "customer_found": $CUSTOMER_FOUND,
    "customer_id": "${CUST_ID}",
    "db_state": {
        "first_name": "$DB_FIRST",
        "last_name": "$DB_LAST",
        "job_title": "$DB_TITLE",
        "notes": "$DB_NOTES",
        "background_info": "$DB_BG",
        "phone": "$DB_PHONE"
    },
    "ground_truth": $GROUND_TRUTH
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="