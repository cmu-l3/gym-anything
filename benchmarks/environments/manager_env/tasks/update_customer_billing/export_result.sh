#!/bin/bash
set -e
echo "=== Exporting update_customer_billing results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TIMESTAMP=$(date -Iseconds)

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# EXTRACT DATA FROM MANAGER.IO VIA CURL
# ------------------------------------------------------------------

COOKIE_FILE="/tmp/mgr_export_cookies.txt"
MANAGER_URL="http://localhost:8080"
OUTPUT_JSON="/tmp/task_result.json"

# Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" -L -o /dev/null 2>/dev/null

# Get Business Key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L 2>/dev/null)
BIZ_KEY=$(python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html)
if not m: m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
" <<< "$BIZ_PAGE")

# Get Customers List
CUST_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/customers?$BIZ_KEY" -L 2>/dev/null)

# Count instances of "Ernst Handel" (to detect duplicates)
ERNST_COUNT=$(echo "$CUST_PAGE" | grep -o "Ernst Handel" | wc -l)

# Find the View/Edit link for Ernst Handel
# We look for the link immediately preceding the text "Ernst Handel" in the table
ERNST_LINK=$(python3 -c "
import re, sys
html = sys.stdin.read()
# Find href like /customer-view?Key=... for Ernst Handel
m = re.search(r'href=\"([^\"]+)\"[^>]*>Ernst Handel', html)
if m: print(m.group(1), end='')
" <<< "$CUST_PAGE")

CUSTOMER_FOUND="false"
CUSTOMER_DETAILS=""
ADDRESS_FOUND="false"
EMAIL_FOUND="false"
OLD_ADDRESS_FOUND="false"
OLD_EMAIL_FOUND="false"

if [ -n "$ERNST_LINK" ]; then
    CUSTOMER_FOUND="true"
    # Fetch details page
    DETAILS_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL$ERNST_LINK" -L 2>/dev/null)
    
    # Check for new values in HTML
    # We use simple grep checks here, more complex verification happens in python
    if echo "$DETAILS_HTML" | grep -q "Musterstra"; then ADDRESS_FOUND="true"; fi
    if echo "$DETAILS_HTML" | grep -q "e.handel@ernsthandel.at"; then EMAIL_FOUND="true"; fi
    
    # Check for old values (should be gone)
    if echo "$DETAILS_HTML" | grep -q "Kirchgasse"; then OLD_ADDRESS_FOUND="true"; fi
    if echo "$DETAILS_HTML" | grep -q "ernst.handel@example.at"; then OLD_EMAIL_FOUND="true"; fi
    
    # Escape HTML for JSON embedding (simple replacement)
    CUSTOMER_DETAILS=$(echo "$DETAILS_HTML" | python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))")
else
    CUSTOMER_DETAILS="null"
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
# We embed the raw HTML of the customer detail page so the python verifier can parse it robustly
cat > "$OUTPUT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "customer_found": $CUSTOMER_FOUND,
    "ernst_count": $ERNST_COUNT,
    "address_found_simple": $ADDRESS_FOUND,
    "email_found_simple": $EMAIL_FOUND,
    "old_address_found_simple": $OLD_ADDRESS_FOUND,
    "old_email_found_simple": $OLD_EMAIL_FOUND,
    "customer_details_html": $CUSTOMER_DETAILS,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 "$OUTPUT_JSON"

echo "Export complete. Result saved to $OUTPUT_JSON"