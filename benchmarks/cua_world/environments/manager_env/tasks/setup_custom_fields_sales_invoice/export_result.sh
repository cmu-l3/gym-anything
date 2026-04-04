#!/bin/bash
echo "=== Exporting setup_custom_fields_sales_invoice result ==="

source /workspace/scripts/task_utils.sh

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"

# 1. Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Extract Data via API/HTML scraping
# We need to verify:
# A) The fields exist in the Custom Fields list
# B) The fields appear on the Sales Invoice form

# Retrieve business key (saved in setup or scrape again)
if [ -f /tmp/biz_key.txt ]; then
    BIZ_KEY=$(cat /tmp/biz_key.txt)
else
    # Try to re-scrape if missing
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null
    BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
    BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | grep -v "create-new-business" | head -1 | cut -d'?' -f2)
fi

echo "Using Business Key: $BIZ_KEY"

# Scrape "Custom Fields" settings page
CUSTOM_FIELDS_HTML=""
SALES_FORM_HTML=""

if [ -n "$BIZ_KEY" ]; then
    # Get Custom Fields list
    CUSTOM_FIELDS_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/custom-fields?$BIZ_KEY" -L)
    
    # Get New Sales Invoice Form
    SALES_FORM_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-invoice-form?$BIZ_KEY" -L)
fi

# 3. Analyze HTML with Python for robustness
# We embed a small python script to parse the HTML and output JSON results
python3 -c "
import sys
import json
import re

try:
    cf_html = sys.stdin.read()
    # Split input by delimiter we create below
    parts = cf_html.split('|||SPLIT|||')
    cf_page = parts[0] if len(parts) > 0 else ''
    form_page = parts[1] if len(parts) > 1 else ''

    # Check Custom Fields List Page
    # Look for the exact names in the table/list
    po_in_list = 'Customer PO Number' in cf_page
    veh_in_list = 'Vehicle Registration' in cf_page
    
    # Check Sales Invoice Form Page
    # Look for labels or input placeholders
    # The form usually renders custom fields as labels
    po_on_form = 'Customer PO Number' in form_page
    veh_on_form = 'Vehicle Registration' in form_page
    
    # Anti-gaming: Check strict timestamps? 
    # (Manager doesn't expose creation timestamps easily in HTML, 
    # so we rely on the fact they weren't there in setup)
    
    result = {
        'po_in_list': po_in_list,
        'veh_in_list': veh_in_list,
        'po_on_form': po_on_form,
        'veh_on_form': veh_on_form,
        'biz_key_found': True
    }
except Exception as e:
    result = {
        'error': str(e),
        'biz_key_found': False
    }

print(json.dumps(result))
" << EOF > /tmp/analysis_result.json
$CUSTOM_FIELDS_HTML
|||SPLIT|||
$SALES_FORM_HTML
EOF

# 4. Construct Final JSON Result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Merge analysis with metadata
jq -s '.[0] + {
    "task_start": '$TASK_START', 
    "task_end": '$TASK_END', 
    "app_running": '$APP_RUNNING',
    "screenshot_path": "/tmp/task_final.png"
}' /tmp/analysis_result.json > /tmp/task_result.json

# Cleanup and Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="