#!/bin/bash
echo "=== Exporting track_real_estate_investment result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/RealEstatePortfolio.xml"

# Check if file was modified
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    MODIFIED=$(file_modified_after "$PORTFOLIO_FILE" /tmp/task_start_marker)
    if [ "$MODIFIED" == "true" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Python script to parse the complex XML structure
python3 << PYEOF > /tmp/re_analysis.json
import xml.etree.ElementTree as ET
import json
import os

result = {
    "file_exists": False,
    "file_modified": $FILE_MODIFIED, # Python boolean from bash string? No, handle below
    "security_found": False,
    "security_name": "",
    "buy_txn_found": False,
    "buy_amount": 0,
    "buy_date": "",
    "dividend_count": 0,
    "dividend_total": 0,
    "price_entries": []
}

filepath = "$PORTFOLIO_FILE"
if os.path.exists(filepath):
    result["file_exists"] = True
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # 1. Check for Security
        target_uuid = None
        securities = root.find("securities")
        if securities is not None:
            for sec in securities.findall("security"):
                name = sec.find("name").text if sec.find("name") is not None else ""
                if "Oak Street" in name or "Rental" in name:
                    result["security_found"] = True
                    result["security_name"] = name
                    target_uuid = sec.find("uuid").text if sec.find("uuid") is not None else None
                    
                    # 4. Check for Prices on this security
                    prices = sec.find("prices")
                    if prices is not None:
                        for p in prices.findall("price"):
                            result["price_entries"].append({
                                "date": p.get("t"),
                                "value": int(p.get("v", 0)) / 10000.0 # PP stores prices scaled
                            })
                    break
        
        # 2. Check for Buy Transaction (Portfolio Transaction)
        # PP stores buys in portfolio->transactions->portfolio-transaction
        # It references the security
        if target_uuid:
            for port in root.iter("portfolio"):
                txns = port.find("transactions")
                if txns is not None:
                    for pt in txns.findall("portfolio-transaction"):
                        # Check type
                        pt_type = pt.find("type").text if pt.find("type") is not None else ""
                        if pt_type == "BUY":
                            # Check security reference
                            sec_ref = pt.find("security")
                            ref_str = sec_ref.get("reference") if sec_ref is not None else ""
                            
                            # Reference might be UUID or xpath
                            if ref_str == target_uuid or target_uuid in ref_str:
                                # Found the buy
                                result["buy_txn_found"] = True
                                amt = pt.find("amount")
                                result["buy_amount"] = int(amt.text)/100.0 if amt is not None else 0
                                date = pt.find("date")
                                result["buy_date"] = date.text if date is not None else ""

        # 3. Check for Dividends (Account Transactions)
        # Dividends are usually Account Transactions linked to the security
        # But in XML they appear under account->transactions->account-transaction
        # with type=DIVIDENDS and usually a security reference
        for acct in root.iter("account"):
            txns = acct.find("transactions")
            if txns is not None:
                for at in txns.findall("account-transaction"):
                    at_type = at.find("type").text if at.find("type") is not None else ""
                    if at_type == "DIVIDENDS":
                        # Verify it's for our security if possible (might be linked)
                        # PP often links via a specialized field or just note
                        # We'll count all dividends since this is a clean portfolio
                        result["dividend_count"] += 1
                        amt = at.find("amount")
                        val = int(amt.text)/100.0 if amt is not None else 0
                        result["dividend_total"] += val

    except Exception as e:
        result["error"] = str(e)

# Fix boolean for file_modified which came from bash
result["file_modified"] = "$FILE_MODIFIED" == "true"

print(json.dumps(result))
PYEOF

# Move result to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/re_analysis.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="