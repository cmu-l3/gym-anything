#!/bin/bash
set -e
echo "=== Exporting create_delivery_note result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Data
MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_verify_cookies_final.txt"
BIZ_KEY=$(cat /tmp/manager_biz_key.txt 2>/dev/null)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Login to API
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" \
    -L -o /dev/null 2>/dev/null

# Access Delivery Notes list
echo "Checking Delivery Notes module status..."
DN_LIST_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/delivery-notes?$BIZ_KEY" -L -w "\nHTTP_CODE:%{http_code}" 2>/dev/null)

HTTP_CODE=$(echo "$DN_LIST_PAGE" | grep "HTTP_CODE:" | cut -d: -f2)
MODULE_ENABLED="false"
# If we get a 200 and the page contains "New Delivery Note", the module is active
if [ "$HTTP_CODE" == "200" ] && echo "$DN_LIST_PAGE" | grep -q "New Delivery Note"; then
    MODULE_ENABLED="true"
fi

# Count notes
NOTE_COUNT=$(echo "$DN_LIST_PAGE" | grep -o "delivery-note-view" | wc -l)
INITIAL_COUNT=$(cat /tmp/initial_dn_count.txt 2>/dev/null || echo "0")
NEW_NOTES_CREATED=$((NOTE_COUNT - INITIAL_COUNT))

# Extract details of the most recent note
LATEST_NOTE_URL=$(echo "$DN_LIST_PAGE" | grep -oP 'delivery-note-view\?[^"]+' | head -1)
NOTE_CONTENT=""
CUSTOMER_MATCH="false"
DATE_MATCH="false"
ITEM1_MATCH="false"
ITEM2_MATCH="false"
ADDRESS_MATCH="false"

if [ -n "$LATEST_NOTE_URL" ]; then
    echo "Fetching details for note: $LATEST_NOTE_URL"
    NOTE_CONTENT=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/$LATEST_NOTE_URL" -L 2>/dev/null)
    
    # Check Customer (Ernst Handel)
    if echo "$NOTE_CONTENT" | grep -qi "Ernst Handel"; then CUSTOMER_MATCH="true"; fi
    
    # Check Date (2025-01-15) - handle various display formats
    if echo "$NOTE_CONTENT" | grep -qE "15/01/2025|01/15/2025|2025-01-15|15 Jan.*2025"; then DATE_MATCH="true"; fi
    
    # Check Item 1 (Chai, 24)
    if echo "$NOTE_CONTENT" | grep -qi "Chai" && echo "$NOTE_CONTENT" | grep -q "24"; then ITEM1_MATCH="true"; fi
    
    # Check Item 2 (Chang, 12)
    if echo "$NOTE_CONTENT" | grep -qi "Chang" && echo "$NOTE_CONTENT" | grep -q "12"; then ITEM2_MATCH="true"; fi
    
    # Check Address/Notes
    if echo "$NOTE_CONTENT" | grep -qi "loading dock"; then ADDRESS_MATCH="true"; fi
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "module_enabled": $MODULE_ENABLED,
    "initial_count": $INITIAL_COUNT,
    "final_count": $NOTE_COUNT,
    "new_notes_created": $NEW_NOTES_CREATED,
    "latest_note": {
        "exists": $([ -n "$LATEST_NOTE_URL" ] && echo "true" || echo "false"),
        "customer_match": $CUSTOMER_MATCH,
        "date_match": $DATE_MATCH,
        "item_chai_match": $ITEM1_MATCH,
        "item_chang_match": $ITEM2_MATCH,
        "address_match": $ADDRESS_MATCH
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="