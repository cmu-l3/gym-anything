#!/bin/bash
echo "=== Exporting reconcile_disconnected_transfers result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/disconnected_transfers.xml"
TASK_START_MARKER="/tmp/task_start_marker"

# Check if file was modified
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    if file_modified_after "$PORTFOLIO_FILE" "$TASK_START_MARKER" | grep -q "true"; then
        FILE_MODIFIED="true"
    fi
fi

# Analyze the XML structure using Python
# We need to check:
# 1. Are the REMOVAL/DEPOSIT transactions gone?
# 2. Are there TRANSFER transactions instead?
# 3. Do they match the dates/amounts?

python3 << PYEOF > /tmp/reconcile_result.json
import xml.etree.ElementTree as ET
import json
import os

result = {
    "file_exists": False,
    "file_modified": $FILE_MODIFIED, # injected from bash
    "removals_count": 0,
    "deposits_count": 0,
    "transfers_out_count": 0,
    "transfers_in_count": 0,
    "correct_transfer_1": False, # 2500 on May 15
    "correct_transfer_2": False, # 1200 on May 28
    "errors": []
}

filepath = "$PORTFOLIO_FILE"

if os.path.exists(filepath):
    result["file_exists"] = True
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Iterate through all account transactions
        # Note: A Transfer in PP is often stored as two linked transactions:
        # Source Account: TRANSFER_OUT
        # Target Account: TRANSFER_IN
        # They are linked via crossEntry attribute or similar mechanism
        
        all_txns = []
        for account in root.findall(".//account"):
            acct_name = account.find("name").text
            for txn in account.findall(".//account-transaction"):
                txn_data = {
                    "account": acct_name,
                    "type": txn.find("type").text,
                    "amount": int(txn.find("amount").text),
                    "date": txn.find("date").text,
                    "note": txn.find("note").text if txn.find("note") is not None else ""
                }
                all_txns.append(txn_data)
                
        # Analyze transactions
        for txn in all_txns:
            amt = txn["amount"]
            date = txn["date"]
            typ = txn["type"]
            
            # Count remaining wrong types for the specific task amounts
            if typ == "REMOVAL" and amt in [250000, 120000]:
                result["removals_count"] += 1
            if typ == "DEPOSIT" and amt in [250000, 120000]:
                result["deposits_count"] += 1
                
            # Count transfers
            if typ == "TRANSFER_OUT":
                result["transfers_out_count"] += 1
                # Check specifics
                if amt == 250000 and "2024-05-15" in date and "Main Checking" in txn["account"]:
                    result["correct_transfer_1"] = True
                if amt == 120000 and "2024-05-28" in date and "Main Checking" in txn["account"]:
                    result["correct_transfer_2"] = True
                    
            if typ == "TRANSFER_IN":
                result["transfers_in_count"] += 1
                
    except Exception as e:
        result["errors"].append(str(e))

with open("/tmp/reconcile_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to safe location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/reconcile_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="