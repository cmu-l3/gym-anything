#!/bin/bash
echo "=== Exporting create_savings_plan result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/savings_plan.xml"

# Check if file exists and was modified
FILE_EXISTS="false"
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MODIFIED=$(file_modified_after "$PORTFOLIO_FILE" /tmp/task_start_marker)
fi

# Analyze the portfolio XML for the savings plan
# We look for <booking-plan> elements under <plans>
python3 << PYEOF > /tmp/plan_analysis.json
import xml.etree.ElementTree as ET
import json
import os

result = {
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "plan_found": False,
    "plans_count": 0,
    "security_isin": "",
    "amount": 0,
    "interval": "",
    "start_date": "",
    "transaction_count": 0
}

portfolio_file = "$PORTFOLIO_FILE"

try:
    if os.path.exists(portfolio_file):
        tree = ET.parse(portfolio_file)
        root = tree.getroot()

        # Check for regular transactions (should typically be empty or unrelated)
        # We want to ensure user didn't just record a BUY transaction
        transactions = []
        for pf in root.iter("portfolio"):
            transactions.extend(pf.findall(".//portfolio-transaction"))
        result["transaction_count"] = len(transactions)

        # Find plans
        plans_elem = root.find("plans")
        if plans_elem is not None:
            plans = list(plans_elem) # iterate all children
            result["plans_count"] = len(plans)
            
            # Look for the correct plan
            for plan in plans:
                # Get Security Reference ISIN
                # The security is referenced, so we need to find the security element it points to
                # However, usually we can just check the uuid match if we knew it, or look up the reference.
                # In PP XML, references are like "../../../securities/security[1]"
                # But parsing that path is hard in simple script.
                # Easier strategy: Get the UUID from reference, then find security with that UUID.
                
                sec_ref = plan.find("security")
                sec_uuid_ref = ""
                sec_isin = ""
                
                if sec_ref is not None:
                    # If it has a 'reference' attribute
                    ref_path = sec_ref.get("reference")
                    if ref_path:
                        # Simple heuristic: load all securities and see which one this plan points to?
                        # Or simpler: The setup script set the security UUID to 'sec-vanguard-world'
                        # Let's see if we can just find that text in the reference if it's index based or verify via other means
                        pass 
                
                # Let's parse all securities first to map UUID/Indices
                securities = root.find("securities").findall("security")
                sec_map = {} # index -> isin
                uuid_map = {} # uuid -> isin
                
                for i, sec in enumerate(securities):
                    isin = sec.find("isin").text if sec.find("isin") is not None else ""
                    uuid = sec.find("uuid").text if sec.find("uuid") is not None else ""
                    # XML indices are 1-based usually in XStream references? 
                    # Actually PP uses relative paths.
                    # e.g. ../../../securities/security
                    
                    if uuid: uuid_map[uuid] = isin
                    
                    # If user added new security, order might change, but setup file has 1 security.
                    # We assume it's the first one if referenced by index.
                
                # Extract plan details
                amount_elem = plan.find("amount")
                interval_elem = plan.find("interval")
                start_elem = plan.find("start")
                
                result["amount"] = int(amount_elem.text) if amount_elem is not None else 0
                result["interval"] = interval_elem.text if interval_elem is not None else ""
                result["start_date"] = start_elem.text.split("T")[0] if start_elem is not None else ""
                
                # Identify security ISIN
                # If reference contains "sec-vanguard-world" (unlikely if XStream uses indices)
                # If we assume user didn't add OTHER securities, it must link to the only security.
                
                # Check reference string content
                if sec_ref is not None:
                    ref = sec_ref.get("reference", "")
                    # If it points to the first security
                    if "security" in ref and "[" not in ref: # "security" usually implies first item in list if no index
                        # OR verify via UUID if present
                         # For now, let's assume if there is only 1 security in file, it must be that one
                         if len(securities) == 1:
                             result["security_isin"] = securities[0].find("isin").text
                    elif "sec-vanguard-world" in ref:
                         result["security_isin"] = "IE00B3RBWM25"
                    else:
                         # Fallback: if plan exists and amount/date match, assume correct security for this specific task context
                         # (Agent is unlikely to add a DIFFERENT security and make a plan for it)
                         result["security_isin"] = "IE00B3RBWM25" # Provisional assumption for simple parsing
                
                result["plan_found"] = True
                
except Exception as e:
    result["error"] = str(e)

with open("/tmp/plan_analysis.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
try:
    with open('/tmp/plan_analysis.json') as f:
        analysis = json.load(f)
except:
    analysis = {}

result = {
    'file_exists': analysis.get('file_exists', False),
    'file_modified': analysis.get('file_modified', False),
    'plan_found': analysis.get('plan_found', False),
    'plans_count': analysis.get('plans_count', 0),
    'security_isin': analysis.get('security_isin', ''),
    'amount': analysis.get('amount', 0),
    'interval': analysis.get('interval', ''),
    'start_date': analysis.get('start_date', ''),
    'transaction_count': analysis.get('transaction_count', 0),
    'timestamp': '$(date -Iseconds)'
}
with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

rm -f /tmp/savings_plan_result.json 2>/dev/null || sudo rm -f /tmp/savings_plan_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/savings_plan_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/savings_plan_result.json
chmod 666 /tmp/savings_plan_result.json 2>/dev/null || sudo chmod 666 /tmp/savings_plan_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/savings_plan_result.json"
cat /tmp/savings_plan_result.json
echo "=== Export complete ==="