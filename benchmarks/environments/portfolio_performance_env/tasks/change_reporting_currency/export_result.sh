#!/bin/bash
echo "=== Exporting Change Reporting Currency Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/us_portfolio.xml"
CSV_FILE="/home/ga/Documents/PortfolioData/eur_usd_rates.csv"

# Check if file exists and was modified
FILE_EXISTS="false"
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MODIFIED=$(file_modified_after "$PORTFOLIO_FILE" /tmp/task_start_marker)
fi

# Analyze the XML content using Python
# We need to check:
# 1. <baseCurrency> or <clientCurrency> is EUR
# 2. A security exists for exchange rates (often has specific attributes or found in securities list)
# 3. That exchange rate security has price data loaded

python3 << PYEOF > /tmp/currency_analysis.json
import xml.etree.ElementTree as ET
import json
import os

result = {
    "file_exists": False,
    "file_modified": False,
    "base_currency": "",
    "exchange_rates_found": False,
    "exchange_rate_data_count": 0,
    "exchange_rate_sample": None,
    "error": None
}

try:
    filepath = "$PORTFOLIO_FILE"
    if os.path.exists(filepath):
        result["file_exists"] = True
        
        # Check modification
        marker = "/tmp/task_start_marker"
        if os.path.exists(marker):
            result["file_modified"] = os.path.getmtime(filepath) > os.path.getmtime(marker)
        
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # 1. Check Base Currency
        # Usually <baseCurrency>USD</baseCurrency> directly under root
        base_curr = root.find("baseCurrency")
        if base_curr is not None:
            result["base_currency"] = base_curr.text
            
        # 2. Check for Exchange Rate Data
        # Exchange rates are stored as securities. 
        # We look for a security that likely represents EUR (ticker EUR, name EUR, or ISIN EUR)
        # and has price data.
        securities = root.findall(".//security")
        for sec in securities:
            name = sec.find("name")
            ticker = sec.find("tickerSymbol")
            isin = sec.find("isin")
            
            n_text = name.text if name is not None else ""
            t_text = ticker.text if ticker is not None else ""
            i_text = isin.text if isin is not None else ""
            
            # Check if this looks like the EUR currency pair
            # Common identifiers: "EUR", "USD/EUR", "EUR/USD"
            is_currency_pair = False
            if "EUR" in t_text or "EUR" in i_text or "Euro" in n_text or "EUR" in n_text:
                is_currency_pair = True
                
            if is_currency_pair:
                prices = sec.find("prices")
                if prices is not None:
                    price_list = prices.findall("price")
                    count = len(price_list)
                    if count > 0:
                        result["exchange_rates_found"] = True
                        result["exchange_rate_data_count"] = count
                        # Get a sample
                        p = price_list[0]
                        result["exchange_rate_sample"] = {"t": p.get("t"), "v": p.get("v")}
                        # If we found one with data, we can stop searching, 
                        # but ideally we want the one that matches the CSV. 
                        # Since user might have multiple, finding ANY with data is good signal.
                        break
                        
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "timestamp": "$(date -Iseconds)",
    "analysis": $(cat /tmp/currency_analysis.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="