#!/bin/bash
echo "=== Exporting record_outbound_delivery result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/gift_transfer_portfolio.xml"
TASK_START_MARKER="/tmp/task_start_marker"

# Python script to analyze the XML file
python3 << PYEOF > /tmp/outbound_delivery_result.json
import xml.etree.ElementTree as ET
import json
import os
import time

result = {
    "file_exists": False,
    "file_modified": False,
    "delivery_found": False,
    "delivery_details": {},
    "sell_found": False,
    "cash_balance_changed": False,
    "initial_share_count": 0,
    "final_share_count": 0
}

filepath = "$PORTFOLIO_FILE"
marker_path = "$TASK_START_MARKER"

if os.path.exists(filepath):
    result["file_exists"] = True
    
    # Check modification time
    if os.path.exists(marker_path):
        result["file_modified"] = os.path.getmtime(filepath) > os.path.getmtime(marker_path)
    
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # 1. Analyze Portfolio Transactions (Securities Account)
        # Look for DELIVERY_OUTBOUND
        # shares are stored as long integer * 100,000,000 (10^8)
        # amount is stored as integer cents
        
        portfolio_txns = []
        for portfolio in root.iter("portfolio"):
            for txn in portfolio.findall(".//portfolio-transaction"):
                txn_type = txn.find("type").text if txn.find("type") is not None else ""
                
                # Check for Outbound Delivery
                if txn_type == "DELIVERY_OUTBOUND":
                    shares_node = txn.find("shares")
                    shares = int(shares_node.text) / 100000000.0 if shares_node is not None else 0
                    
                    amount_node = txn.find("amount")
                    amount = int(amount_node.text) / 100.0 if amount_node is not None else 0
                    
                    date_node = txn.find("date")
                    date = date_node.text if date_node is not None else ""
                    
                    # Check security reference
                    sec_ref = ""
                    sec_node = txn.find("security")
                    if sec_node is not None:
                        sec_ref = sec_node.get("reference", "")
                    
                    # Store found delivery
                    result["delivery_found"] = True
                    result["delivery_details"] = {
                        "shares": shares,
                        "amount": amount,
                        "date": date,
                        "security_ref": sec_ref
                    }
                
                # Check if user mistakenly recorded a SELL
                if txn_type == "SELL":
                    result["sell_found"] = True
        
        # 2. Analyze Cash Account Transactions
        # A true Delivery (Outbound) should NOT create a cash deposit
        # A Sell would create a DEPOSIT or have a crossEntry
        
        # We check if there are any new DEPOSIT/INTEREST transactions after the initial one
        cash_txns = []
        for account in root.iter("account"):
            for txn in account.findall(".//account-transaction"):
                uuid = txn.find("uuid").text if txn.find("uuid") is not None else ""
                # Ignore the initial deposit we created in setup
                if uuid != "txn-dep-initial":
                     # If we find any other transaction impacting cash, flag it
                     result["cash_balance_changed"] = True
        
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/outbound_delivery_result.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/outbound_delivery_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="