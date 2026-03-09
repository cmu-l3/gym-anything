#!/bin/bash
# Export script for setup_financial_controls task
# Scrapes Manager.io pages to verify configuration

echo "=== Exporting task results ==="

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Login (to get cookies/session)
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" \
    -L -o /dev/null

# 3. Get Business Key
# We need the key (e.g., 'start?Key=...') to construct URLs
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses")

# Extract key using Python for robustness
BIZ_KEY=$(python3 -c "
import sys, re
html = sys.stdin.read()
# Look for Northwind Traders link
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html)
if not m:
    # Fallback to any start link
    m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '')
" <<< "$BIZ_PAGE")

echo "Business Key: $BIZ_KEY"

# 4. Verify Lock Date
# Fetch the Lock Date form page
LOCK_DATE_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/lock-date-form?$BIZ_KEY")

# Extract value from input field: <input ... value="2024-12-31" ... >
LOCK_DATE_VALUE=$(echo "$LOCK_DATE_HTML" | grep -oP 'name="LockDate"[^>]*value="\K[^"]*' || echo "")

echo "Detected Lock Date: $LOCK_DATE_VALUE"

# 5. Verify Form Defaults (Sales Invoice)
# Instead of finding the specific default setting page (which has complex IDs),
# we simply request the 'New Sales Invoice' form. 
# If defaults are set correctly, the Footer field will be pre-filled.
NEW_INVOICE_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/sales-invoice-form?$BIZ_KEY")

# Extract textarea content for Footer (often named 'CustomFields' or 'Footer')
# Manager.io field names can vary, usually it's name="Footer" or similar.
# We look for the text area content.
FOOTER_VALUE=$(python3 -c "
import sys, re
html = sys.stdin.read()
# Find textarea with name ending in Footer or close to it
# Pattern: <textarea ... name=\"...Footer...\">CONTENT</textarea>
m = re.search(r'<textarea[^>]*name=\"[^\"]*Footer[^\"]*\"[^>]*>(.*?)</textarea>', html, re.DOTALL)
if m:
    print(m.group(1))
else:
    print('')
" <<< "$NEW_INVOICE_HTML")

# Decode HTML entities (e.g., &#10; for newlines)
FOOTER_VALUE_DECODED=$(python3 -c "import html, sys; print(html.unescape(sys.argv[1]))" "$FOOTER_VALUE")

echo "Detected Footer Value length: ${#FOOTER_VALUE_DECODED}"

# 6. Capture Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, os, sys
result = {
    'lock_date_value': os.environ.get('LOCK_DATE_VALUE', ''),
    'footer_value': os.environ.get('FOOTER_VALUE_DECODED', ''),
    'task_start': int(os.environ.get('TASK_START', 0)),
    'task_end': int(os.environ.get('TASK_END', 0)),
    'business_key_found': bool(os.environ.get('BIZ_KEY', ''))
}
print(json.dumps(result))
" > "$TEMP_JSON"

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="