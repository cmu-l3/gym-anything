#!/bin/bash
echo "=== Exporting record_asset_depreciation result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# API Setup
COOKIE_FILE="/tmp/mgr_cookies.txt"
MANAGER_URL="http://localhost:8080"

# Re-login to ensure session
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get Business Key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | head -1 | cut -d'?' -f2)

# 1. Check if DepreciationEntries module is enabled
# We check the tabs-form value or check if the endpoint is accessible
MODULE_ENABLED="false"
# Try to access the module page. If disabled, Manager usually redirects or shows error, 
# but API inspection of tabs is safer.
TABS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/tabs-form?$BIZ_KEY" -L)
# Check if "DepreciationEntries":true is present in the value="{...}" JSON
if echo "$TABS_PAGE" | grep -q '"DepreciationEntries":true'; then
    MODULE_ENABLED="true"
fi

# 2. Fetch Depreciation Entries
# We need to parse the HTML list of depreciation entries
ENTRIES_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/depreciation-entries?$BIZ_KEY" -L)

# Simple parsing: Manager.io tables usually contain the data in <td> tags
# We look for our target values in the HTML
ENTRY_FOUND="false"
FOUND_DATE=""
FOUND_AMOUNT=""
FOUND_DESC=""
FOUND_ASSET=""

# Check for specific content in the page
# We look for row containing "Ford Transit" AND "4,500.00" (or 4500.00) AND "31/12/2024" or "2024-12-31"
# Note: Manager.io formatting depends on locale, assuming US/standard format "4,500.00"

if echo "$ENTRIES_PAGE" | grep -q "Ford Transit"; then
    FOUND_ASSET="true"
else
    FOUND_ASSET="false"
fi

# Check for amount (flexible formatting)
if echo "$ENTRIES_PAGE" | grep -E "4,500\.00|4500\.00"; then
    FOUND_AMOUNT="true"
else
    FOUND_AMOUNT="false"
fi

# Check for date (flexible formatting: 31/12/2024 or 12/31/2024 or 2024-12-31)
if echo "$ENTRIES_PAGE" | grep -E "31/12/2024|12/31/2024|2024-12-31|31 Dec 2024|Dec 31, 2024"; then
    FOUND_DATE="true"
else
    FOUND_DATE="false"
fi

# 3. Capture Screenshot
take_screenshot /tmp/task_final.png

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "module_enabled": $MODULE_ENABLED,
    "entry_found_asset": $FOUND_ASSET,
    "entry_found_amount": $FOUND_AMOUNT,
    "entry_found_date": $FOUND_DATE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json