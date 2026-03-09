#!/bin/bash
echo "=== Exporting create_multicurrency_portfolio result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target file
TARGET_FILE="/home/ga/Documents/PortfolioData/multicurrency_portfolio.xml"
TASK_START_MARKER="/tmp/task_start_marker"

# Check if file exists
FILE_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    # Check if modified/created after task start
    if [ "$TARGET_FILE" -nt "$TASK_START_MARKER" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Python script to analyze the XML content
python3 << PYEOF > /tmp/portfolio_analysis.json
import xml.etree.ElementTree as ET
import json
import os
import sys

result = {
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "base_currency": None,
    "accounts": [],
    "portfolios": [],
    "securities": [],
    "deposit_txns": [],
    "buy_txns": []
}

target_file = "$TARGET_FILE"

if result["file_exists"]:
    try:
        tree = ET.parse(target_file)
        root = tree.getroot()

        # 1. Base Currency
        bc = root.find("baseCurrency")
        if bc is not None:
            result["base_currency"] = bc.text

        # 2. Securities
        # Map UUID to ISIN for transaction checking
        security_map = {} 
        
        securities_elem = root.find("securities")
        if securities_elem is not None:
            for sec in securities_elem.findall("security"):
                sec_data = {
                    "uuid": sec.findtext("uuid", ""),
                    "name": sec.findtext("name", ""),
                    "isin": sec.findtext("isin", ""),
                    "currency": sec.findtext("currencyCode", "")
                }
                result["securities"].append(sec_data)
                security_map[sec_data["uuid"]] = sec_data

        # 3. Deposit Accounts & Deposit Transactions
        accounts_elem = root.find("accounts")
        if accounts_elem is not None:
            for acc in accounts_elem.findall("account"):
                acc_data = {
                    "name": acc.findtext("name", ""),
                    "currency": acc.findtext("currencyCode", ""),
                    "uuid": acc.findtext("uuid", "")
                }
                result["accounts"].append(acc_data)
                
                # Check transactions inside account
                txns_elem = acc.find("transactions")
                if txns_elem is not None:
                    for txn in txns_elem.findall("account-transaction"):
                        t_type = txn.findtext("type", "")
                        if t_type == "DEPOSIT":
                            amt_str = txn.findtext("amount", "0")
                            try:
                                amt = float(amt_str) / 100.0 # PP stores cents
                            except:
                                amt = 0.0
                                
                            result["deposit_txns"].append({
                                "account_name": acc_data["name"],
                                "currency": txn.findtext("currencyCode", ""),
                                "amount": amt,
                                "date": txn.findtext("date", "")
                            })

        # 4. Portfolios (Depots) & Buy Transactions
        portfolios_elem = root.find("portfolios")
        if portfolios_elem is not None:
            for port in portfolios_elem.findall("portfolio"):
                port_data = {
                    "name": port.findtext("name", ""),
                    "reference_account": ""
                }
                
                # Try to find linked reference account
                ref_node = port.find("referenceAccount")
                if ref_node is not None:
                    port_data["reference_account"] = ref_node.get("reference", "")
                    
                result["portfolios"].append(port_data)
                
                # Check transactions inside portfolio
                txns_elem = port.find("transactions")
                if txns_elem is not None:
                    for txn in txns_elem.findall("portfolio-transaction"):
                        t_type = txn.findtext("type", "")
                        if t_type == "BUY":
                            # Resolve security
                            sec_node = txn.find("security")
                            sec_isin = "UNKNOWN"
                            sec_currency = "UNKNOWN"
                            
                            if sec_node is not None:
                                # Reference can be relative path or UUID match
                                ref = sec_node.get("reference", "")
                                # Simple UUID match attempt
                                for uuid, data in security_map.items():
                                    if uuid in ref: # Loose match for relative paths containing uuid
                                        sec_isin = data["isin"]
                                        sec_currency = data["currency"]
                                        break
                                # If still unknown, try to match by order if using index referencing (rare in new PP)
                                
                            # Amounts
                            try:
                                # Shares in PP are stored as value * 10^9 (usually) or 10^something
                                # But let's look at the raw value first. 
                                # For XML export, shares="20000000000" usually means 20.000000000
                                shares_raw = float(txn.findtext("shares", "0"))
                                shares = shares_raw / 100000000.0 # Heuristic: PP usually 10^8 for sorting?
                                # Actually PP uses 100000000 for internal Calc, let's verify logic 
                                # 25 shares -> 2500000000? 
                                # Let's just output raw and fix in verifier or use normalized logic
                                shares = shares_raw / 100000000.0 # Standard seems to be 10^8
                                
                                # Amount is in cents
                                amount = float(txn.findtext("amount", "0")) / 100.0
                                
                                # Fees
                                fees = 0.0
                                for unit in txn.findall(".//unit"):
                                    if unit.get("type") == "FEE":
                                        fees += float(unit.findtext("amount", "0")) / 100.0
                            except:
                                shares = 0
                                amount = 0
                                fees = 0
                            
                            result["buy_txns"].append({
                                "portfolio_name": port_data["name"],
                                "isin": sec_isin,
                                "sec_currency": sec_currency,
                                "date": txn.findtext("date", ""),
                                "shares_raw": shares_raw, # Pass raw for flexible verification
                                "amount": amount,
                                "fees": fees
                            })

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/portfolio_analysis.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv /tmp/portfolio_analysis.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Analysis complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="