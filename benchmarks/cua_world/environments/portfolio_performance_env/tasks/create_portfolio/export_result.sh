#!/bin/bash
echo "=== Exporting create_portfolio result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_file_count 2>/dev/null | tr -d '[:space:]' || echo "0")
[ -z "$INITIAL_COUNT" ] && INITIAL_COUNT="0"

# Search for the expected portfolio file
TARGET_DIR="/home/ga/Documents/PortfolioData"
PORTFOLIO_FILE=""
PORTFOLIO_FOUND="false"
PORTFOLIO_NAME=""
FILE_CURRENCY=""
HAS_SECURITIES_ACCOUNT="false"
HAS_CASH_ACCOUNT="false"
SECURITIES_ACCOUNT_NAME=""
CASH_ACCOUNT_NAME=""

# Look for retirement_portfolio files
for f in $(find "$TARGET_DIR" -name "*retirement*" \( -name "*.xml" -o -name "*.portfolio" \) 2>/dev/null); do
    PORTFOLIO_FILE="$f"
    PORTFOLIO_FOUND="true"
    break
done

# If not found by name, look for any new portfolio file
if [ "$PORTFOLIO_FOUND" = "false" ]; then
    for f in $(find "$TARGET_DIR" -name "*.xml" -newer /tmp/task_start_marker 2>/dev/null); do
        PORTFOLIO_FILE="$f"
        PORTFOLIO_FOUND="true"
        break
    done
fi

# Also check home directory and recent files
if [ "$PORTFOLIO_FOUND" = "false" ]; then
    for f in $(find /home/ga -maxdepth 3 -name "*retirement*" \( -name "*.xml" -o -name "*.portfolio" \) 2>/dev/null); do
        PORTFOLIO_FILE="$f"
        PORTFOLIO_FOUND="true"
        break
    done
fi

# If still not found, look for any recently modified PP file
if [ "$PORTFOLIO_FOUND" = "false" ]; then
    LATEST=$(find /home/ga -maxdepth 4 \( -name "*.xml" -o -name "*.portfolio" \) -newer /tmp/task_start_marker -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
    if [ -n "$LATEST" ]; then
        PORTFOLIO_FILE="$LATEST"
        PORTFOLIO_FOUND="true"
    fi
fi

# Parse the portfolio file if found
if [ "$PORTFOLIO_FOUND" = "true" ] && [ -f "$PORTFOLIO_FILE" ]; then
    PORTFOLIO_NAME=$(basename "$PORTFOLIO_FILE" | sed 's/\.\(xml\|portfolio\)$//')

    # Extract currency
    FILE_CURRENCY=$(grep -oP '<baseCurrency>\K[^<]+' "$PORTFOLIO_FILE" 2>/dev/null || echo "")
    if [ -z "$FILE_CURRENCY" ]; then
        FILE_CURRENCY=$(grep -oP 'baseCurrency="[^"]*"' "$PORTFOLIO_FILE" 2>/dev/null | head -1 | sed 's/baseCurrency="//;s/"//' || echo "")
    fi

    # Extract securities account (portfolio) and cash account names via XML parsing
    # IMPORTANT: Use specific element paths to avoid conflating portfolio vs account names
    eval "$(python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('$PORTFOLIO_FILE')
    root = tree.getroot()
    # Securities account = portfolio element name
    portfolios = root.find('portfolios')
    if portfolios is not None:
        p = portfolios.find('portfolio')
        if p is not None:
            name = p.find('name')
            if name is not None and name.text:
                print('HAS_SECURITIES_ACCOUNT=true')
                print('SECURITIES_ACCOUNT_NAME=\"' + name.text.replace('\"', '') + '\"')
    # Cash/deposit account = account element name
    accounts = root.find('accounts')
    if accounts is not None:
        a = accounts.find('account')
        if a is not None:
            name = a.find('name')
            if name is not None and name.text:
                print('HAS_CASH_ACCOUNT=true')
                print('CASH_ACCOUNT_NAME=\"' + name.text.replace('\"', '') + '\"')
except:
    pass
" 2>/dev/null)"
fi

# Count current files
CURRENT_COUNT=$(find "$TARGET_DIR" -name "*.xml" -o -name "*.portfolio" 2>/dev/null | wc -l)

# Check all windows for title info
WINDOW_TITLES=$(wmctrl -l 2>/dev/null | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}' || echo "")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
result = {
    'portfolio_found': $( [ \"$PORTFOLIO_FOUND\" = \"true\" ] && echo 'True' || echo 'False'),
    'portfolio_file': $(python3 -c "import json; print(json.dumps('$PORTFOLIO_FILE'))" 2>/dev/null || echo '""'),
    'portfolio_name': $(python3 -c "import json; print(json.dumps('$PORTFOLIO_NAME'))" 2>/dev/null || echo '""'),
    'file_currency': $(python3 -c "import json; print(json.dumps('$FILE_CURRENCY'))" 2>/dev/null || echo '""'),
    'has_securities_account': $( [ \"$HAS_SECURITIES_ACCOUNT\" = \"true\" ] && echo 'True' || echo 'False'),
    'has_cash_account': $( [ \"$HAS_CASH_ACCOUNT\" = \"true\" ] && echo 'True' || echo 'False'),
    'securities_account_name': $(python3 -c "import json; print(json.dumps('$SECURITIES_ACCOUNT_NAME'))" 2>/dev/null || echo '""'),
    'cash_account_name': $(python3 -c "import json; print(json.dumps('$CASH_ACCOUNT_NAME'))" 2>/dev/null || echo '""'),
    'initial_file_count': int('$INITIAL_COUNT'.strip()),
    'current_file_count': int('$CURRENT_COUNT'.strip()),
    'window_titles': $(python3 -c "import json; print(json.dumps('$WINDOW_TITLES'))" 2>/dev/null || echo '""'),
    'timestamp': '$(date -Iseconds)'
}
with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Move to final location
rm -f /tmp/create_portfolio_result.json 2>/dev/null || sudo rm -f /tmp/create_portfolio_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_portfolio_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_portfolio_result.json
chmod 666 /tmp/create_portfolio_result.json 2>/dev/null || sudo chmod 666 /tmp/create_portfolio_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/create_portfolio_result.json"
cat /tmp/create_portfolio_result.json
echo "=== Export complete ==="
