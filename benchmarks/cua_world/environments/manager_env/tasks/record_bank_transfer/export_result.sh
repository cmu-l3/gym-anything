#!/bin/bash
echo "=== Exporting record_bank_transfer result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

COOKIE_FILE="/tmp/mgr_export_cookies.txt"
rm -f "$COOKIE_FILE"
MANAGER_URL="http://localhost:8080"

# ---------------------------------------------------------------------------
# Login and Get Data
# ---------------------------------------------------------------------------
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" \
    -L -o /dev/null

# Get Business Key
if [ -f /tmp/manager_biz_key.txt ]; then
    BIZ_KEY=$(cat /tmp/manager_biz_key.txt)
else
    # Fallback lookup
    BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
    BIZ_KEY=$(python3 -c "import re, sys; m = re.search(r'start\?([^\"]+).*Northwind', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$BIZ_PAGE")
fi

# Get Inter-Account Transfers List
TRANSFERS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/inter-account-transfers?$BIZ_KEY" -L)
CURRENT_COUNT=$(echo "$TRANSFERS_PAGE" | grep -c 'inter-account-transfer?' || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_transfer_count.txt 2>/dev/null || echo "0")

# Find the most recent transfer link
LATEST_LINK=$(echo "$TRANSFERS_PAGE" | grep -o 'href="[^"]*inter-account-transfer?[^"]*"' | head -1 | cut -d'"' -f2)

TRANSFER_DETAILS_HTML=""
if [ -n "$LATEST_LINK" ]; then
    # Decode HTML entities in URL if needed (curl handles standard URLs)
    # Manager URLs are usually clean.
    TRANSFER_DETAILS_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL$LATEST_LINK" -L)
fi

# ---------------------------------------------------------------------------
# Parse Data with Python
# ---------------------------------------------------------------------------
# We pass the HTML content to python to extract fields robustly
PYTHON_PARSER=$(cat <<'END_PYTHON'
import sys, json, re

html_content = sys.stdin.read()

result = {
    "amount_found": False,
    "date_found": False,
    "source_found": False,
    "dest_found": False,
    "desc_found": False,
    "raw_amount": "",
    "raw_date": "",
    "raw_desc": ""
}

# Simple regex heuristics for Manager.io view mode
# Date often appears in top section
if re.search(r'2024-06-15|15/06/2024|15 Jun 2024', html_content):
    result["date_found"] = True
    result["raw_date"] = "2024-06-15"

# Amount - look for 3,500.00
if re.search(r'3,500\.00|3500\.00', html_content):
    result["amount_found"] = True
    result["raw_amount"] = "3500.00"

# Source Account
if "Cash on Hand" in html_content:
    result["source_found"] = True

# Destination Account
if "Business Checking Account" in html_content:
    result["dest_found"] = True

# Description / Reference
if "1045" in html_content or "deposit" in html_content.lower():
    result["desc_found"] = True
    # Try to extract the line
    m = re.search(r'<div>([^<]*(?:1045|deposit)[^<]*)</div>', html_content, re.IGNORECASE)
    if m:
        result["raw_desc"] = m.group(1).strip()

print(json.dumps(result))
END_PYTHON
)

PARSED_DATA="{}"
if [ -n "$TRANSFER_DETAILS_HTML" ]; then
    PARSED_DATA=$(echo "$TRANSFER_DETAILS_HTML" | python3 -c "$PYTHON_PARSER")
fi

# Check browser status
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then APP_RUNNING="true"; fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "parsed_data": $PARSED_DATA,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"