#!/bin/bash
echo "=== Exporting import_historical_quotes result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get initial count
INITIAL_PRICE_COUNT=$(cat /tmp/initial_price_count 2>/dev/null | tr -d '[:space:]' || echo "0")
[ -z "$INITIAL_PRICE_COUNT" ] && INITIAL_PRICE_COUNT="0"

# Find the portfolio file
PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/investment_portfolio.xml"
PORTFOLIO_FOUND="false"
PRICE_COUNT=0
HAS_AAPL_PRICES="false"
FIRST_DATE=""
LAST_DATE=""
FILE_MODIFIED="false"

# Check if the file was modified
if [ -f "$PORTFOLIO_FILE" ]; then
    PORTFOLIO_FOUND="true"
    FILE_MODIFIED=$(file_modified_after "$PORTFOLIO_FILE" /tmp/task_start_marker)

    # Count prices in the file
    PRICE_COUNT=$(grep -c '<price ' "$PORTFOLIO_FILE" 2>/dev/null || true)
    [ -z "$PRICE_COUNT" ] && PRICE_COUNT="0"

    # Parse the XML for AAPL price data
    python3 << PYEOF > /tmp/price_analysis.json
import xml.etree.ElementTree as ET
import json

result = {
    "has_aapl_prices": False,
    "aapl_price_count": 0,
    "first_date": "",
    "last_date": "",
    "sample_prices": []
}

try:
    tree = ET.parse("$PORTFOLIO_FILE")
    root = tree.getroot()

    securities_elem = root.find("securities")
    security_list = securities_elem.findall("security") if securities_elem is not None else []
    for sec in security_list:
        name_elem = sec.find("name")
        ticker_elem = sec.find("tickerSymbol")
        if name_elem is not None and ("Apple" in (name_elem.text or "") or
            (ticker_elem is not None and ticker_elem.text == "AAPL")):
            prices_elem = sec.find("prices")
            if prices_elem is not None:
                prices = prices_elem.findall("price")
                if len(prices) > 0:
                    result["has_aapl_prices"] = True
                    result["aapl_price_count"] = len(prices)
                    dates = sorted([p.get("t", "") for p in prices])
                    result["first_date"] = dates[0] if dates else ""
                    result["last_date"] = dates[-1] if dates else ""
                    # Sample first 5 prices
                    for p in prices[:5]:
                        result["sample_prices"].append({
                            "date": p.get("t", ""),
                            "value": p.get("v", "")
                        })
            break
except Exception as e:
    result["parse_error"] = str(e)

with open("/tmp/price_analysis.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

    # Read the analysis
    if [ -f /tmp/price_analysis.json ]; then
        HAS_AAPL_PRICES=$(python3 -c "import json; d=json.load(open('/tmp/price_analysis.json')); print('true' if d.get('has_aapl_prices') else 'false')")
        AAPL_PRICE_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/price_analysis.json')); print(d.get('aapl_price_count', 0))")
        FIRST_DATE=$(python3 -c "import json; d=json.load(open('/tmp/price_analysis.json')); print(d.get('first_date', ''))")
        LAST_DATE=$(python3 -c "import json; d=json.load(open('/tmp/price_analysis.json')); print(d.get('last_date', ''))")
    fi
fi

# Also check for any other recently saved portfolio files
LATEST_FILE=$(find /home/ga -maxdepth 4 \( -name "*.xml" -o -name "*.portfolio" \) -newer /tmp/task_start_marker -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json

# Load price analysis if available
price_analysis = {}
try:
    with open('/tmp/price_analysis.json') as f:
        price_analysis = json.load(f)
except:
    pass

result = {
    'portfolio_found': $( [ \"$PORTFOLIO_FOUND\" = \"true\" ] && echo 'True' || echo 'False'),
    'portfolio_file': '$PORTFOLIO_FILE',
    'file_modified': $( [ \"$FILE_MODIFIED\" = \"true\" ] && echo 'True' || echo 'False'),
    'initial_price_count': int('$INITIAL_PRICE_COUNT'.strip()),
    'current_price_count': int('$PRICE_COUNT'.strip()),
    'has_aapl_prices': price_analysis.get('has_aapl_prices', False),
    'aapl_price_count': price_analysis.get('aapl_price_count', 0),
    'first_date': price_analysis.get('first_date', ''),
    'last_date': price_analysis.get('last_date', ''),
    'sample_prices': price_analysis.get('sample_prices', []),
    'latest_modified_file': '${LATEST_FILE}',
    'timestamp': '$(date -Iseconds)'
}
with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

rm -f /tmp/import_quotes_result.json 2>/dev/null || sudo rm -f /tmp/import_quotes_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/import_quotes_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/import_quotes_result.json
chmod 666 /tmp/import_quotes_result.json 2>/dev/null || sudo chmod 666 /tmp/import_quotes_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/import_quotes_result.json"
cat /tmp/import_quotes_result.json
echo "=== Export complete ==="
