#!/bin/bash
echo "=== Exporting record_mortgage_payment result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/NetWorthPortfolio.xml"
# Check if a new file was saved (handling Save As scenarios)
LATEST_FILE=$(find /home/ga/Documents/PortfolioData -name "*.xml" -newer /tmp/task_start_marker -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
if [ -n "$LATEST_FILE" ]; then
    PORTFOLIO_FILE="$LATEST_FILE"
fi

# Python script to analyze the portfolio XML and calculate final balances
# We cannot simply grep amounts because PP might store transactions as separate entries
# We need to sum up deposits, withdrawals, transfers, interest, fees, etc.
python3 << PYEOF > /tmp/mortgage_result.json
import xml.etree.ElementTree as ET
import json
import os

result = {
    "file_exists": False,
    "file_modified": False,
    "checking_balance": 0,
    "mortgage_balance": 0,
    "expense_txn_found": False,
    "transfer_found": False,
    "error": ""
}

filepath = "$PORTFOLIO_FILE"

try:
    if os.path.exists(filepath):
        result["file_exists"] = True
        
        # Check timestamp
        start_marker = "/tmp/task_start_marker"
        if os.path.exists(start_marker):
            result["file_modified"] = os.path.getmtime(filepath) > os.path.getmtime(start_marker)
        
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Calculate balances for each account
        for account in root.findall(".//account"):
            name = account.find("name").text
            balance = 0
            
            for txn in account.findall(".//account-transaction"):
                amount = int(txn.find("amount").text)
                txn_type = txn.find("type").text
                
                # Logic for balance calculation based on transaction type
                # PP internal storage: 
                # DEPOSIT: +amount
                # REMOVAL: -amount
                # INTEREST: +amount (income)
                # FEES/TAXES: -amount (expense)
                # BUY/SELL/TRANSFER... handled via cross entries usually, but let's look at raw amounts
                
                # However, for simple account analysis without resolving cross-entries fully:
                # Transfers usually appear as TRANSFER_OUT (-amount) and TRANSFER_IN (+amount)
                
                if txn_type == "DEPOSIT":
                    balance += amount
                elif txn_type == "REMOVAL":
                    balance -= amount
                elif txn_type == "INTEREST":
                    # Interest can be income (positive) or expense (negative flow context)
                    # In PP XML, Interest is usually income. 
                    # If user recorded expense as Interest Charge (negative), PP might store it as a specific type or negative amount?
                    # Actually, PP usually treats Interest as Income. Expenses are FEES or TAXES.
                    # But if the user enters a negative value...
                    balance += amount
                elif txn_type == "FEES" or txn_type == "TAXES":
                    balance -= amount
                elif txn_type == "TRANSFER_OUT":
                    balance -= amount
                    result["transfer_found"] = True
                elif txn_type == "TRANSFER_IN":
                    balance += amount
                    result["transfer_found"] = True
                
                # Check for our specific expense transaction
                # We are looking for an expense of ~130000 cents
                if amount == 130000 and (txn_type in ["FEES", "TAXES", "INTEREST_CHARGE"]):
                     result["expense_txn_found"] = True
                # If they recorded it as a removal named "Interest"
                if amount == 130000 and txn_type == "REMOVAL":
                     note = txn.find("note")
                     if note is not None and "interest" in (note.text or "").lower():
                         result["expense_txn_found"] = True

            if "Checking" in name:
                result["checking_balance"] = balance
            elif "Mortgage" in name:
                result["mortgage_balance"] = balance

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Fix permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/mortgage_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="