#!/bin/bash
echo "=== Exporting import_csv_transactions result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/us_tech_portfolio.xml"
TASK_START_MARKER="/tmp/task_start_marker"

# Check if file was modified
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ] && [ "$PORTFOLIO_FILE" -nt "$TASK_START_MARKER" ]; then
    FILE_MODIFIED="true"
fi

# Use Python to analyze the XML content
# We extract: total count, type counts, and a list of transactions to verify values
python3 << PYEOF > /tmp/import_result.json
import xml.etree.ElementTree as ET
import json
import os

result = {
    "file_exists": False,
    "file_modified": False,
    "total_txns": 0,
    "buy_count": 0,
    "sell_count": 0,
    "transactions": [],
    "error": ""
}

filepath = "$PORTFOLIO_FILE"
file_modified_str = "$FILE_MODIFIED"

if os.path.exists(filepath):
    result["file_exists"] = True
    result["file_modified"] = (file_modified_str == "true")

    try:
        tree = ET.parse(filepath)
        root = tree.getroot()

        # PP stores transactions in <portfolio-transaction> elements nested in <portfolio>
        # We need to find all of them
        txns = []
        for pf in root.findall(".//portfolio"):
             txns.extend(pf.findall(".//portfolio-transaction"))
        
        result["total_txns"] = len(txns)
        
        for txn in txns:
            t_type = txn.find("type").text if txn.find("type") is not None else "UNKNOWN"
            
            # Amount and Shares are stored as integers (scaled). 
            # Amount usually scaled by 100 (cents), Shares by 1,000,000,000? 
            # Actually PP XML format varies, but usually:
            # <amount>185590</amount> -> 1855.90
            # <shares>10000000000</shares> -> 10.00000000
            
            amount_elem = txn.find("amount")
            shares_elem = txn.find("shares")
            date_elem = txn.find("date")
            
            amount_raw = int(amount_elem.text) if amount_elem is not None else 0
            shares_raw = int(shares_elem.text) if shares_elem is not None else 0
            date_str = date_elem.text if date_elem is not None else ""
            
            # Fee extraction
            fees = 0
            for unit in txn.findall(".//unit"):
                if unit.get("type") == "FEE":
                    amt = unit.find("amount")
                    if amt is not None:
                        fees += int(amt.get("amount", "0"))

            # Normalize values
            # PP amount is usually factor 100
            amount = amount_raw / 100.0
            fees = fees / 100.0
            
            # Shares is usually factor 1,000,000,000 (10^9)
            shares = shares_raw / 1_000_000_000.0

            if t_type == "BUY":
                result["buy_count"] += 1
            elif t_type == "SELL":
                result["sell_count"] += 1

            result["transactions"].append({
                "type": t_type,
                "date": date_str,
                "amount": amount,
                "shares": shares,
                "fees": fees
            })
            
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

print(json.dumps(result, indent=2))
PYEOF

# Move result to safe location with permissions
mv /tmp/import_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="