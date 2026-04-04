#!/bin/bash
echo "=== Exporting Contractor Invoice Result ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state screenshot
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/Documents/GreenLeaf_Invoice_1024.odt"
RESULT_JSON="/tmp/task_result.json"

# Python script to parse ODT XML and extract formula information
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import xml.etree.ElementTree as ET

output_file = "/home/ga/Documents/GreenLeaf_Invoice_1024.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "text_content": "",
    "formula_count": 0,
    "currency_format_count": 0,
    "calculated_values": [],
    "formulas_found": [],
    "error": None
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            content_xml = zf.read('content.xml').decode('utf-8')
            
            # Extract plain text for content check
            # Simple regex to strip tags
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
            result["text_content"] = plain_text
            
            # Parse XML to find tables and formulas
            # Namespaces are tricky in ElementTree, usually better to strip or handle explicitly
            # Here we'll use regex for robustness against namespace variations in ODF
            
            # Find cells with formulas
            # Pattern looks for table:formula="oooc:=..."
            # Note: ODF uses 'table:formula' attribute
            formula_matches = re.findall(r'table:formula\s*=\s*"([^"]+)"', content_xml)
            result["formula_count"] = len(formula_matches)
            result["formulas_found"] = formula_matches
            
            # Find cells with currency formatting
            # This often appears as office:value-type="currency"
            currency_matches = re.findall(r'office:value-type\s*=\s*"currency"', content_xml)
            result["currency_format_count"] = len(currency_matches)
            
            # Extract calculated values from cells that have formulas
            # We look for table:table-cell elements that have BOTH formula and value
            # This is complex with regex, so we'll do a simple value extraction
            # Looking for office:value="..."
            values = re.findall(r'office:value\s*=\s*"([0-9.]+)"', content_xml)
            # Convert to float
            result["calculated_values"] = [float(v) for v in values]
            
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export complete. Found {result['formula_count']} formulas.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="