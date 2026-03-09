#!/bin/bash
echo "=== Exporting batch_import_customers results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Basic Setup
MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"
BIZ_KEY=$(cat /tmp/biz_key.txt 2>/dev/null || echo "")

# Login (refresh session)
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# 3. Get Final Customer Data
# Fetch the customers page
CUST_PAGE=$(curl -s -b "$COOKIE_FILE" "$MANAGER_URL/customers?$BIZ_KEY" -L)

# Count customers
FINAL_COUNT=$(echo "$CUST_PAGE" | grep -o 'view-customer' | wc -l || echo 0)
INITIAL_COUNT=$(cat /tmp/initial_customer_count.txt 2>/dev/null || echo 0)

# Check for specific names
NAMES_FOUND=0
NAMES_TO_CHECK=("Bon app'" "Bottom-Dollar Markets" "Cactus Comidas para llevar" "Die Wandernde Kuh")
FOUND_LIST=()

for name in "${NAMES_TO_CHECK[@]}"; do
    # Simple grep check in the HTML
    if echo "$CUST_PAGE" | grep -Fq "$name"; then
        NAMES_FOUND=$((NAMES_FOUND + 1))
        FOUND_LIST+=("$name")
    fi
done

# 4. Check specific data integrity (Email for "Die Wandernde Kuh")
# We need to find the UUID/link for this customer to inspect details
# Regex to find the link: <td ...><a href="view-customer?Key=...">Die Wandernde Kuh</a>
# This is tricky with regex/grep alone on raw HTML.
# We will do a broad check: does the HTML of the list page contain the email?
# Manager list views typically show emails if columns are enabled, but might not.
# Better: Search the customer list HTML for the email.
EMAIL_CHECK_PASSED="false"
TARGET_EMAIL="orders@wanderndekuh.de"

if echo "$CUST_PAGE" | grep -Fq "$TARGET_EMAIL"; then
    EMAIL_CHECK_PASSED="true"
else
    # If not in list view, we might need to drill down, but that's hard in bash.
    # We will assume if the name is there, the agent likely imported the row.
    # To be stricter, we check if the text file was read.
    pass
fi

# 5. Check if source file was accessed (Read timestamp)
FILE_ACCESSED="false"
SOURCE_FILE="/home/ga/Documents/new_leads.tsv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)
FILE_ATIME=$(stat -c %X "$SOURCE_FILE" 2>/dev/null || echo 0)

if [ "$FILE_ATIME" -gt "$TASK_START" ]; then
    FILE_ACCESSED="true"
fi

# 6. Prepare JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "names_found_count": $NAMES_FOUND,
    "names_found_list": $(printf '%s\n' "${FOUND_LIST[@]}" | jq -R . | jq -s .),
    "email_visible_in_list": $EMAIL_CHECK_PASSED,
    "source_file_accessed": $FILE_ACCESSED,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="