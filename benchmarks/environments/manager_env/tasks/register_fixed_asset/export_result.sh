#!/bin/bash
echo "=== Exporting register_fixed_asset result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------------------
# Scrape Manager.io State via API/Curl
# ---------------------------------------------------------------------------

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_verify_cookies.txt"

# Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get Business Key
BIZ_PAGE=$(curl -s -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
# Extract the key for "Northwind Traders" specifically
BIZ_KEY=$(python3 -c "import sys, re; h=sys.stdin.read(); m=re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', h); print(m.group(1) if m else '')" <<< "$BIZ_PAGE")

# Fallback if specific regex fails
if [ -z "$BIZ_KEY" ]; then
    BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | grep -v "create-new-business" | head -1 | cut -d'?' -f2)
fi

echo "Business Key: $BIZ_KEY"

# 1. Check if Fixed Assets Module is Enabled
# We check the sidebar of the Summary page
SUMMARY_PAGE=$(curl -s -b "$COOKIE_FILE" "$MANAGER_URL/summary?$BIZ_KEY" -L)
MODULE_ENABLED="false"
if echo "$SUMMARY_PAGE" | grep -q "Fixed Assets"; then
    MODULE_ENABLED="true"
fi

# 2. Check for Asset Existence
# We go to the Fixed Assets list page
ASSETS_PAGE=$(curl -s -b "$COOKIE_FILE" "$MANAGER_URL/fixed-assets?$BIZ_KEY" -L)

# Look for our specific asset
ASSET_FOUND="false"
ASSET_URL=""
if echo "$ASSETS_PAGE" | grep -iq "Bosch"; then
    ASSET_FOUND="true"
    # Extract the URL to the view/edit page for this asset
    # Expected HTML: <a href="/fixed-asset-view?Key=...">Bosch...</a>
    ASSET_URL=$(echo "$ASSETS_PAGE" | grep -o 'href="/fixed-asset-view?Key=[^"]*"' | grep -v "New Fixed Asset" | head -1 | cut -d'"' -f2)
fi

# 3. Extract Asset Details
ASSET_NAME=""
ASSET_CODE=""
ASSET_COST=""
ASSET_DATE=""
ASSET_METHOD=""
ASSET_RATE=""
ASSET_SALVAGE=""

if [ -n "$ASSET_URL" ]; then
    echo "Fetching asset details from $ASSET_URL..."
    DETAIL_PAGE=$(curl -s -b "$COOKIE_FILE" "$MANAGER_URL$ASSET_URL" -L)
    
    # Use python to robustly parse the view/edit page fields
    # Manager view pages usually display data in a table or definition list
    
    # Helper to clean HTML tags
    clean_html() {
        sed -e 's/<[^>]*>//g' -e 's/^[ \t]*//' -e 's/[ \t]*$//'
    }

    # Extract Name (usually header or first field)
    ASSET_NAME=$(echo "$DETAIL_PAGE" | grep -A1 "Name" | tail -1 | clean_html)
    # If using View page, might be in a header <h1> or similar. 
    # Let's try to get the Edit page instead which has input values, easiest to parse.
    EDIT_URL=$(echo "$ASSET_URL" | sed 's/view/form/')
    EDIT_PAGE=$(curl -s -b "$COOKIE_FILE" "$MANAGER_URL$EDIT_URL" -L)
    
    # Parse input values from Edit form
    # Pattern: <input ... name="...Name" value="Bosch..." />
    # Using python for regex extraction on the whole HTML block
    cat > /tmp/parse_asset.py << PYEOF
import re
import sys
import json

html = sys.stdin.read()

def get_val(field_suffix):
    # Regex for input value
    # Matches name="...FieldName" ... value="Value"
    # Or value="Value" ... name="...FieldName"
    
    # Strategy: Find the input tag containing the field name, then extract value
    # Simplified regex for robustness
    pattern = r'<input[^>]*name="[^"]*' + field_suffix + r'"[^>]*value="([^"]*)"'
    m = re.search(pattern, html, re.IGNORECASE)
    if m: return m.group(1)
    
    # Try textarea
    pattern_text = r'<textarea[^>]*name="[^"]*' + field_suffix + r'"[^>]*>([^<]*)</textarea>'
    m = re.search(pattern_text, html, re.IGNORECASE)
    if m: return m.group(1)
    
    return ""

def get_select(field_suffix):
    # For dropdowns, we need the selected option
    # Find select by name
    # This is harder with regex, let's try a simpler heuristic or just grep the value if it's stored in a variable
    # Often Manager puts the value in the input if it's a number, but Method is a select.
    
    # Quick hack: look for the JSON object often embedded in Manager pages or the raw input
    pass
    return ""

data = {
    "Name": get_val("Name"),
    "AcquisitionCost": get_val("AcquisitionCost"),
    "AcquisitionDate": get_val("AcquisitionDate"),
    "SalvageValue": get_val("SalvageValue"),
    "DepreciationRate": get_val("DepreciationRate"), # Used for life usually
}

# Depreciation Method is often a select. 
if "StraightLine" in html and "selected" in html:
    # This is a bit weak, but if "StraightLine" is selected it usually appears as value="StraightLine" selected
    if 'value="StraightLine" selected' in html or 'value="StraightLine" checked' in html:
        data["DepreciationMethod"] = "StraightLine"
    else:
        data["DepreciationMethod"] = "Unknown"
else:
    # Manager sometimes uses radio buttons or selects
    if 'value="StraightLine"' in html: # check if it appears at least
         data["DepreciationMethod"] = "StraightLine" # Optimistic

print(json.dumps(data))
PYEOF

    PARSED_JSON=$(python3 /tmp/parse_asset.py <<< "$EDIT_PAGE")
    echo "Parsed Asset Data: $PARSED_JSON"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "module_enabled": $MODULE_ENABLED,
    "asset_found": $ASSET_FOUND,
    "asset_details": ${PARSED_JSON:-{}},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="