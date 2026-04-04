#!/bin/bash
echo "=== Exporting correct_misassigned_transactions result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/misassigned_trades.xml"

# Check if file exists and was modified
FILE_EXISTS="false"
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MODIFIED=$(file_modified_after "$PORTFOLIO_FILE" /tmp/task_start_marker)
fi

# Analyze the XML structure to verify transaction locations
python3 << PYEOF > /tmp/transaction_locations.json
import xml.etree.ElementTree as ET
import json
import os

result = {
    "file_exists": False,
    "file_modified": False,
    "retirement_bnd_count": 0,
    "retirement_nvda_count": 0,
    "retirement_amd_count": 0,
    "speculative_bnd_count": 0,
    "speculative_nvda_count": 0,
    "speculative_amd_count": 0,
    "total_txns": 0,
    "integrity_check": True
}

filepath = "$PORTFOLIO_FILE"

if os.path.exists(filepath):
    result["file_exists"] = True
    
    # Check modification time against marker
    try:
        marker_mtime = os.path.getmtime("/tmp/task_start_marker")
        file_mtime = os.path.getmtime(filepath)
        if file_mtime > marker_mtime:
            result["file_modified"] = True
    except:
        pass

    try:
        tree = ET.parse(filepath)
        root = tree.getroot()

        # Map security UUIDs to Tickers
        uuid_to_ticker = {}
        for sec in root.findall(".//security"):
            uuid = sec.find("uuid")
            ticker = sec.find("tickerSymbol")
            if uuid is not None and ticker is not None:
                uuid_to_ticker[uuid.text] = ticker.text

        # Analyze portfolios
        for portfolio in root.findall(".//portfolio"):
            name_elem = portfolio.find("name")
            p_name = name_elem.text if name_elem is not None else "Unknown"
            
            # Determine which account this is
            is_retirement = "Retirement" in p_name
            is_speculative = "Speculative" in p_name

            # Iterate transactions
            transactions = portfolio.find("transactions")
            if transactions is not None:
                for txn in transactions.findall("portfolio-transaction"):
                    result["total_txns"] += 1
                    
                    # Identify security
                    sec_ref = txn.find("security")
                    ticker = "Unknown"
                    if sec_ref is not None:
                        ref = sec_ref.get("reference")
                        # Handle direct reference or relative path? 
                        # PP often uses relative paths in references like "../../../securities/security[1]"
                        # But we can try to find the UUID if we are lucky, or infer from context
                        # For robust verification, we might need to rely on the fact that we created the file
                        # with specific order: sec[1]=NVDA, sec[2]=AMD, sec[3]=BND
                        
                        if "security[1]" in ref: ticker = "NVDA"
                        elif "security[2]" in ref: ticker = "AMD"
                        elif "security[3]" in ref: ticker = "BND"
                        else:
                            # Try to match by UUID if possible (harder with relative paths)
                            pass

                    # Increment counters based on location and ticker
                    if is_retirement:
                        if ticker == "BND": result["retirement_bnd_count"] += 1
                        elif ticker == "NVDA": result["retirement_nvda_count"] += 1
                        elif ticker == "AMD": result["retirement_amd_count"] += 1
                    elif is_speculative:
                        if ticker == "BND": result["speculative_bnd_count"] += 1
                        elif ticker == "NVDA": result["speculative_nvda_count"] += 1
                        elif ticker == "AMD": result["speculative_amd_count"] += 1

    except Exception as e:
        result["error"] = str(e)
        result["integrity_check"] = False

print(json.dumps(result))
PYEOF

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
try:
    with open('/tmp/transaction_locations.json') as f:
        data = json.load(f)
except:
    data = {}

# Add metadata
data['timestamp'] = '$(date -Iseconds)'

with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f, indent=2)
"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="