#!/bin/bash
echo "=== Exporting record_short_sale_trade result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Path to the portfolio file
PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/margin_account.xml"

# Check if file exists and was modified
FILE_EXISTS="false"
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MODIFIED=$(file_modified_after "$PORTFOLIO_FILE" /tmp/task_start_marker)
fi

# Python script to parse the XML and extract transaction details
python3 << PYEOF > /tmp/short_sale_analysis.json
import xml.etree.ElementTree as ET
import json
import os
import sys

result = {
    "file_exists": False,
    "file_modified": False,
    "pton_security_found": False,
    "sell_txn_found": False,
    "buy_txn_found": False,
    "sell_details": {},
    "buy_details": {},
    "net_shares": 0,
    "parse_error": None
}

filepath = "$PORTFOLIO_FILE"
start_marker = "/tmp/task_start_marker"

if os.path.exists(filepath):
    result["file_exists"] = True
    
    # Check modification time
    try:
        if os.path.exists(start_marker):
            result["file_modified"] = os.path.getmtime(filepath) > os.path.getmtime(start_marker)
    except:
        pass

    try:
        tree = ET.parse(filepath)
        root = tree.getroot()

        # 1. Find PTON Security
        # We need the UUID to identify transactions linked to it
        pton_uuid = None
        securities = root.find("securities")
        if securities is not None:
            for sec in securities.findall("security"):
                ticker = sec.find("tickerSymbol")
                isin = sec.find("isin")
                name = sec.find("name")
                
                t_val = ticker.text if ticker is not None else ""
                i_val = isin.text if isin is not None else ""
                n_val = name.text if name is not None else ""
                
                if "PTON" in t_val or "US70614W1009" in i_val or "Peloton" in n_val:
                    result["pton_security_found"] = True
                    pton_uuid = sec.find("uuid").text
                    break
        
        # 2. Find Transactions
        # Transactions are typically inside <portfolio-transaction> elements
        # These can be nested in <portfolio> or <account-transaction> depending on version/structure
        # We'll search recursively for <portfolio-transaction>
        
        txns = []
        for txn in root.iter("portfolio-transaction"):
            # Check if this transaction relates to PTON
            # The security reference might be a UUID or a relative path
            sec_ref = txn.find("security")
            if sec_ref is not None:
                ref_str = sec_ref.get("reference", "")
                
                # Match logic: UUID match OR if it's the only security added
                is_match = False
                if pton_uuid and pton_uuid in ref_str:
                    is_match = True
                elif result["pton_security_found"]: 
                    # If PTON is found, it's likely the newly added one. 
                    # If user added it, it's likely the last one or identified by context.
                    # For robustness, we assume if PTON exists, relevant trades are for it 
                    # (since starting state was empty)
                    is_match = True

                if is_match:
                    t_type = txn.find("type").text
                    t_date = txn.find("date").text
                    t_shares = int(txn.find("shares").text) / 1000000000.0 # PP uses 9 decimals
                    t_amount = int(txn.find("amount").text) / 100.0        # PP uses 2 decimals
                    
                    # Extract fees
                    t_fee = 0.0
                    for unit in txn.findall(".//unit"):
                        if unit.get("type") == "FEE":
                            t_fee = int(unit.find("amount").get("amount")) / 100.0

                    txn_data = {
                        "type": t_type,
                        "date": t_date,
                        "shares": t_shares,
                        "amount": t_amount,
                        "fee": t_fee
                    }
                    txns.append(txn_data)

        # Analyze found transactions
        total_shares = 0
        for t in txns:
            if t["type"] == "SELL" or t["type"] == "DELIVERY_OUTBOUND":
                # Look for the specific Short Sell
                if "2021-07-01" in t["date"] and abs(t["shares"] - 100) < 0.1:
                    result["sell_txn_found"] = True
                    result["sell_details"] = t
                total_shares -= t["shares"]
            
            elif t["type"] == "BUY" or t["type"] == "DELIVERY_INBOUND":
                # Look for the Cover Buy
                if "2022-05-02" in t["date"] and abs(t["shares"] - 100) < 0.1:
                    result["buy_txn_found"] = True
                    result["buy_details"] = t
                total_shares += t["shares"]

        result["net_shares"] = total_shares

    except Exception as e:
        result["parse_error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Move result to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/short_sale_analysis.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json