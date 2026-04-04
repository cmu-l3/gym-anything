#!/bin/bash
# Export script for configure_invoice_defaults task
# Verifies if the defaults were actually applied by fetching a NEW invoice form via API

echo "=== Exporting configure_invoice_defaults results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot of the agent's screen
take_screenshot /tmp/task_final.png

# 2. Get verification data
# We simulate a request to create a NEW sales invoice.
# If defaults are set correctly, the returned HTML/JSON for the new form
# will contain the default values pre-filled.

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"

# Helper to get the business key for Northwind Traders
# (This logic is adapted from setup_data.sh to ensure we target the right business)
echo "Resolving Northwind Traders business key..."
# Trigger login to ensure cookies
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get business list and extract key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(python3 -c "
import sys, re
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html)
if not m: m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '')
" <<< "$BIZ_PAGE")

echo "Business Key: $BIZ_KEY"

# Fetch the "New Sales Invoice" form
# The defaults should appear in this empty form
echo "Fetching New Sales Invoice form to check defaults..."
NEW_FORM_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-invoice-form?$BIZ_KEY" -L)

# 3. Analyze the form content for expected defaults
# We look for the strings in the HTML/JSON model payload
# Manager.io usually embeds the View Model JSON in the HTML or sets input values

# Check Custom Title: "TAX INVOICE"
if echo "$NEW_FORM_HTML" | grep -q "TAX INVOICE"; then
    TITLE_FOUND="true"
else
    TITLE_FOUND="false"
fi

# Check Due Date: "14" (looking for the number 14 associated with due date fields)
# This is trickier, but usually appears as value="14" or in the JSON model
if echo "$NEW_FORM_HTML" | grep -qE "value=\"14\"|:14,|:14}"; then
    DUE_DATE_FOUND="true"
else
    # Broader check for just "14" if context is missing, validated by VLM later
    if echo "$NEW_FORM_HTML" | grep -q "14"; then
        DUE_DATE_FOUND="potential"
    else
        DUE_DATE_FOUND="false"
    fi
fi

# Check Notes: specific snippet
# "Please include invoice number in transfer reference"
NOTES_SNIPPET="include invoice number in transfer reference"
if echo "$NEW_FORM_HTML" | grep -q "$NOTES_SNIPPET"; then
    NOTES_FOUND="true"
else
    NOTES_FOUND="false"
fi

# Check if app was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "title_configured": $TITLE_FOUND,
    "due_date_configured": "$DUE_DATE_FOUND",
    "notes_configured": $NOTES_FOUND,
    "app_was_running": $APP_RUNNING,
    "task_timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permission fix
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="