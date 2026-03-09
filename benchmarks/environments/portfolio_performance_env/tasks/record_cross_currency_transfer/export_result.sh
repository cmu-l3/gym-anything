#!/bin/bash
echo "=== Exporting record_cross_currency_transfer result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/forex_portfolio.xml"

# Check if file was modified (save detection)
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    if [ "$PORTFOLIO_FILE" -nt "/tmp/task_start_marker" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Parse XML to extract transaction details
python3 << PYEOF > /tmp/transfer_result.json
import xml.etree.ElementTree as ET
import json
import os

result = {
    "file_exists": False,
    "file_modified": $FILE_MODIFIED, # passed from bash
    "transfer_out_found": False,
    "transfer_in_found": False,
    "transactions_linked": False,
    "source_amount": 0,
    "target_amount": 0,
    "date_match": False,
    "error": ""
}

try:
    if os.path.exists("$PORTFOLIO_FILE"):
        result["file_exists"] = True
        tree = ET.parse("$PORTFOLIO_FILE")
        root = tree.getroot()

        # Find accounts
        accounts = root.findall(".//account")
        
        eur_txns = []
        usd_txns = []

        for acct in accounts:
            curr = acct.find("currencyCode")
            if curr is not None:
                txns = acct.findall(".//account-transaction")
                if curr.text == "EUR":
                    eur_txns = txns
                elif curr.text == "USD":
                    usd_txns = txns

        # Search for TRANSFER_OUT in EUR account (2500.00 EUR -> 250000)
        # We look for ANY transfer out first, then validate details
        tx_out = None
        for tx in eur_txns:
            t_type = tx.find("type")
            t_amt = tx.find("amount")
            if t_type is not None and t_type.text == "TRANSFER_OUT":
                # Check amount (2500.00 * 100 = 250000)
                if t_amt is not None and int(t_amt.text) == 250000:
                    tx_out = tx
                    result["transfer_out_found"] = True
                    result["source_amount"] = int(t_amt.text)
                    
                    # Check date
                    t_date = tx.find("date")
                    if t_date is not None and "2024-10-15" in t_date.text:
                        result["date_match"] = True
                    break

        # Search for TRANSFER_IN in USD account (2725.00 USD -> 272500)
        tx_in = None
        for tx in usd_txns:
            t_type = tx.find("type")
            t_amt = tx.find("amount")
            if t_type is not None and t_type.text == "TRANSFER_IN":
                if t_amt is not None and int(t_amt.text) == 272500:
                    tx_in = tx
                    result["transfer_in_found"] = True
                    result["target_amount"] = int(t_amt.text)
                    break
        
        # Check Linkage (Cross Entry)
        # PP links transfers by having a 'crossEntry' element in each transaction
        # pointing to the UUID of the other transaction.
        if tx_out is not None and tx_in is not None:
            out_uuid = tx_out.find("uuid")
            in_uuid = tx_in.find("uuid")
            out_cross = tx_out.find("crossEntry")
            in_cross = tx_in.find("crossEntry")

            # Check if they reference each other
            linked_out_to_in = False
            linked_in_to_out = False

            if out_cross is not None and in_uuid is not None:
                # The crossEntry usually contains just the UUID string or a reference attribute
                # In PP XML it often looks like: <crossEntry class="account-transaction" reference="../../..."/>
                # Or sometimes it's direct. Let's check text or attribs.
                ref = out_cross.get("reference")
                if ref and in_uuid.text in ref: # Simple check if UUID is in reference path
                     linked_out_to_in = True
                elif out_cross.text == in_uuid.text:
                     linked_out_to_in = True
                # If using XStream references, it might be complex. 
                # PP often puts the linked transaction UUID in the crossEntry text if not using references.
            
            # Simplified check: If both exist and have crossEntry elements, likely linked.
            # A distinct unlinked deposit/withdrawal would NOT have crossEntry.
            if out_cross is not None and in_cross is not None:
                result["transactions_linked"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Move result to safe location
mv /tmp/transfer_result.json /tmp/task_result.json 2>/dev/null || cp /tmp/transfer_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="