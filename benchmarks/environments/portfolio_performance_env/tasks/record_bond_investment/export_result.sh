#!/bin/bash
echo "=== Exporting record_bond_investment result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/bond_portfolio.xml"

# Check if user saved to a different file (anti-gaming/robustness)
LATEST_FILE=$(find /home/ga -maxdepth 4 \( -name "*.xml" -o -name "*.portfolio" \) -newer /tmp/task_start_marker -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
if [ -n "$LATEST_FILE" ] && [ -f "$LATEST_FILE" ]; then
    PORTFOLIO_FILE="$LATEST_FILE"
fi

# Python script to analyze the XML content
python3 << PYEOF > /tmp/bond_analysis.json
import xml.etree.ElementTree as ET
import json
import os
import sys

result = {
    "file_found": False,
    "file_modified": False,
    "security_found": False,
    "security_isin_match": False,
    "security_name": "",
    "buy_txn_found": False,
    "buy_details": {},
    "interest_txns": [],
    "prices": [],
    "total_interest_amount": 0.0
}

filepath = "$PORTFOLIO_FILE"

try:
    if os.path.exists(filepath):
        result["file_found"] = True
        
        # Check modification time vs task start
        task_start = 0
        if os.path.exists("/tmp/task_start_time"):
            with open("/tmp/task_start_time", "r") as f:
                try:
                    task_start = int(f.read().strip())
                except:
                    pass
        
        if os.path.getmtime(filepath) > task_start:
            result["file_modified"] = True

        tree = ET.parse(filepath)
        root = tree.getroot()

        # 1. Check Security
        # ISIN: US91282CJL54
        target_isin = "US91282CJL54"
        sec_uuid = None
        
        securities_node = root.find("securities")
        if securities_node is not None:
            for sec in securities_node.findall("security"):
                isin_node = sec.find("isin")
                name_node = sec.find("name")
                
                curr_isin = isin_node.text if isin_node is not None else ""
                curr_name = name_node.text if name_node is not None else ""
                
                # Check match
                if target_isin in curr_isin or "Treasury" in curr_name:
                    result["security_found"] = True
                    result["security_name"] = curr_name
                    if target_isin == curr_isin:
                        result["security_isin_match"] = True
                    
                    sec_uuid = sec.find("uuid").text if sec.find("uuid") is not None else None
                    
                    # Extract prices
                    prices_node = sec.find("prices")
                    if prices_node is not None:
                        for p in prices_node.findall("price"):
                            result["prices"].append({
                                "date": p.get("t"),
                                "value": float(p.get("v", 0)) / 100000000.0 if "." not in p.get("v", "0") else float(p.get("v")) 
                                # PP stores prices as long scaled? Actually usually just value="12345" for 123.45 in some versions, 
                                # but standard XML export often uses attributes t="2024-01-01" v="12345" (scaled by 100 or 10000?)
                                # Let's assume standard int format: usually scaled by 10000 or similar, but let's grab raw first.
                                # Actually PP 0.60+ often uses `v="123450000"` for 1.2345. Let's just store raw for verifier to check relative.
                            })
                            # Actually, looking at previous examples, simple int scaling is common.
                            # However, for verifier robustness, let's just capture the raw value attribute.
                            # The verifier can normalize.

        # 2. Check Buy Transaction
        # Look in portfolios -> portfolio -> portfolio-transaction
        # Need to find one linked to our security
        for portfolio in root.iter("portfolio"):
            for txn in portfolio.findall(".//portfolio-transaction"):
                type_node = txn.find("type")
                if type_node is not None and type_node.text == "BUY":
                    # Check security reference
                    sec_ref = txn.find("security")
                    ref_uuid = sec_ref.get("reference") if sec_ref is not None else ""
                    
                    # Resolve reference (could be ../../../securities/security[1] or UUID)
                    is_match = False
                    if sec_uuid and sec_uuid in ref_uuid:
                        is_match = True
                    elif "Treasury" in result["security_name"]: 
                        # Fallback if only one security exists
                        is_match = True

                    if is_match:
                        date_node = txn.find("date")
                        shares_node = txn.find("shares")
                        amount_node = txn.find("amount")
                        
                        shares = int(shares_node.text)/100000000.0 if shares_node is not None else 0 # PP uses high precision ints
                        # Actually PP usually 10^8 for shares
                        
                        amount = int(amount_node.text)/100.0 if amount_node is not None else 0 # PP usually 10^2 for currency
                        
                        # Store details
                        result["buy_txn_found"] = True
                        result["buy_details"] = {
                            "date": date_node.text if date_node is not None else "",
                            "shares": shares,
                            "amount": amount
                        }

        # 3. Check Interest Transactions
        # Look in accounts -> account -> transactions -> account-transaction
        for account in root.iter("account"):
            for txn in account.findall(".//account-transaction"):
                type_node = txn.find("type")
                if type_node is not None and type_node.text == "INTEREST":
                    amount_node = txn.find("amount")
                    date_node = txn.find("date")
                    
                    amount = int(amount_node.text)/100.0 if amount_node is not None else 0
                    date = date_node.text if date_node is not None else ""
                    
                    result["interest_txns"].append({
                        "date": date,
                        "amount": amount
                    })
                    result["total_interest_amount"] += amount

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions on result file
chmod 666 /tmp/bond_analysis.json 2>/dev/null || true
cp /tmp/bond_analysis.json /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete."
cat /tmp/task_result.json