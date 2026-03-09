#!/bin/bash
echo "=== Exporting Clean Historical Quote Outliers result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Parameters
PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/amzn_glitch.xml"
INITIAL_COUNT=$(cat /tmp/initial_price_count 2>/dev/null || echo "20")

# Check if file was modified
FILE_MODIFIED="false"
if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_MODIFIED=$(file_modified_after "$PORTFOLIO_FILE" /tmp/task_start_marker)
fi

# Analyze the XML to check for the outlier
# The glitch was $0.01. Valid data is > $100.00.
# Threshold: 50.00 USD -> 50 * 100,000,000 = 5000000000
THRESHOLD="5000000000"

python3 << PYEOF > /tmp/analysis_result.json
import xml.etree.ElementTree as ET
import json
import os

result = {
    "file_exists": False,
    "file_modified": False,
    "initial_count": int("$INITIAL_COUNT"),
    "final_count": 0,
    "outliers_found": 0,
    "min_price_val": 0,
    "min_price_date": "",
    "data_preserved": False,
    "outlier_removed": False
}

filepath = "$PORTFOLIO_FILE"
threshold = $THRESHOLD

if os.path.exists(filepath):
    result["file_exists"] = True
    result["file_modified"] = "$FILE_MODIFIED" == "true"
    
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        prices = []
        # Find prices in AMZN security
        for sec in root.findall(".//security"):
            name = sec.find("name")
            if name is not None and "Amazon" in (name.text or ""):
                prices_elem = sec.find("prices")
                if prices_elem is not None:
                    prices = prices_elem.findall("price")
                break
        
        result["final_count"] = len(prices)
        
        outliers = 0
        min_val = float('inf')
        min_date = ""
        
        for p in prices:
            v_str = p.get("v", "0")
            t_str = p.get("t", "")
            try:
                val = int(v_str)
                if val < min_val:
                    min_val = val
                    min_date = t_str
                
                if val < threshold:
                    outliers += 1
            except:
                pass
                
        result["outliers_found"] = outliers
        result["min_price_val"] = min_val if min_val != float('inf') else 0
        result["min_price_date"] = min_date
        
        # Logic checks
        result["outlier_removed"] = (outliers == 0)
        
        # Valid count should be Initial - 1 (the glitch) or Initial (if glitch fixed but not deleted)
        # But instructions say "Delete".
        # Initial was 20. Target is 19.
        # Allow range [18, 20] to be lenient on accidental deletion of adjacent day
        result["data_preserved"] = (18 <= len(prices) <= 20)

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

# Save result to /tmp/task_result.json for verifier
cp /tmp/analysis_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result analysis:"
cat /tmp/task_result.json
echo "=== Export complete ==="