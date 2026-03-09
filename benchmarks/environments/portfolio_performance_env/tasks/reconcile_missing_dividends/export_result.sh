#!/bin/bash
echo "=== Exporting Reconcile Task Result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_end.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/dividend_audit.xml"
CSV_FILE="/home/ga/Documents/broker_statement_2023.csv"

# Check if file was modified
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_MODIFIED=$(file_modified_after "$PORTFOLIO_FILE" /tmp/task_start_marker)
fi

# Parse the Portfolio XML to extract JNJ Dividends in 2023
# We need to extract: Date, Gross Amount, Taxes for verification
python3 << PYEOF > /tmp/reconcile_result.json
import xml.etree.ElementTree as ET
import json
import os
import datetime

result = {
    "file_exists": False,
    "file_modified": False,
    "dividends": [],
    "total_dividends_count": 0,
    "timestamp": "$(date -Iseconds)"
}

filepath = "$PORTFOLIO_FILE"
start_marker = "/tmp/task_start_marker"

if os.path.exists(filepath):
    result["file_exists"] = True
    
    # Check modification time
    if os.path.exists(start_marker):
        result["file_modified"] = os.path.getmtime(filepath) > os.path.getmtime(start_marker)
    
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # 1. Find JNJ Security UUID (to ensure we look at the right transactions)
        # However, dividends are usually in <account-transaction> and reference security
        
        # 2. Scan all account transactions
        # Structure: <account-transaction> ... <type>DIVIDENDS</type> ... <date> ... <units>
        
        ns = {} # PP XML usually doesn't use complex namespaces in simple exports
        
        for txn in root.iter("account-transaction"):
            try:
                type_node = txn.find("type")
                if type_node is None or type_node.text != "DIVIDENDS":
                    continue
                
                # Check date year
                date_node = txn.find("date")
                if date_node is None:
                    continue
                date_str = date_node.text.split("T")[0] # YYYY-MM-DD
                if not date_str.startswith("2023"):
                    continue
                
                # Extract amounts
                # PP stores values in minor units (e.g. cents), usually defined by base currency
                # But unit amounts might be different.
                
                gross_amt = 0
                tax_amt = 0
                
                units = txn.find("units")
                if units is not None:
                    for unit in units.findall("unit"):
                        u_type = unit.get("type")
                        amt_node = unit.find("amount")
                        if amt_node is not None:
                            val = int(amt_node.get("amount", 0))
                            if u_type == "GROSS_VALUE":
                                gross_amt = val
                            elif u_type == "TAX":
                                tax_amt = val
                
                # Fallback if no units (unlikely for dividends in PP, but possible for simple entries)
                # But for this task, we expect user to enter Gross + Tax to match CSV
                
                div_record = {
                    "date": date_str,
                    "gross_amount": gross_amt / 100.0, # Convert cents to dollars
                    "tax_amount": tax_amt / 100.0
                }
                
                result["dividends"].append(div_record)
                
            except Exception as e:
                print(f"Error parsing transaction: {e}")
                continue
                
        result["total_dividends_count"] = len(result["dividends"])
        
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Save result with permissions
rm -f /tmp/reconcile_final_result.json 2>/dev/null || true
cp /tmp/reconcile_result.json /tmp/reconcile_final_result.json
chmod 666 /tmp/reconcile_final_result.json

echo "Result exported to /tmp/reconcile_final_result.json"
cat /tmp/reconcile_final_result.json
echo "=== Export Complete ==="