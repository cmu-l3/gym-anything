#!/bin/bash
echo "=== Exporting setup_starting_balances result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot() {
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true
}
take_screenshot

# Python script to scrape the actual values from Manager.io
# Manager.io Server Edition is locally accessible.
cat > /tmp/scrape_results.py << 'EOF'
import requests
import re
import json
import sys

MANAGER_URL = "http://localhost:8080"
s = requests.Session()

result = {
    "start_date": None,
    "balances": {},
    "connection_error": False,
    "business_found": False
}

try:
    # Login
    s.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, timeout=10)
    
    # Get Business Key
    r = s.get(f"{MANAGER_URL}/businesses", timeout=10)
    m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', r.text)
    if not m:
        m = re.search(r'start\?([^"&\s]+)', r.text)
    
    if m:
        key = m.group(1)
        result["business_found"] = True
        
        # 1. Check Start Date
        # The form is at /start-date-form?{key}
        r_date = s.get(f"{MANAGER_URL}/start-date-form?{key}", timeout=10)
        # Look for the date input value
        # <input ... name="..." value="2024-07-01" ... type="date">
        # Regex to find date pattern YYYY-MM-DD inside a value attribute
        date_match = re.search(r'value="(\d{4}-\d{2}-\d{2})"', r_date.text)
        if date_match:
            result["start_date"] = date_match.group(1)

        # 2. Check Starting Balances
        # The page is /starting-balances?{key}
        # This page lists accounts and their debits/credits.
        # It's an HTML table. Parsing it with regex is messy but doable for specific values.
        r_balances = s.get(f"{MANAGER_URL}/starting-balances?{key}", timeout=10)
        html = r_balances.text
        
        # We need to find rows containing our target accounts and extract the numbers.
        # Structure often looks like: <td>Account Name</td> ... <td class="text-right">1,234.56</td>
        
        targets = [
            "Cash on Hand",
            "Alfreds Futterkiste",
            "Ernst Handel",
            "Exotic Liquids"
        ]
        
        # Simple scraping strategy: Split by account name, look at the immediate following numbers
        # This is a heuristic but effective for verification.
        
        for target in targets:
            if target in html:
                # Find the chunk of HTML after the target name
                part = html.split(target, 1)[1]
                # Look for the next number formatted like currency (e.g. 25,000.00)
                # We look for simple number patterns inside tags
                # A balance might be in Debit or Credit column.
                
                # Regex for currency: 1,234.56 or 1234.56
                # We grab the first few numbers that look like amounts
                amounts = re.findall(r'>([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})?)<', part[:1000])
                
                # Convert strings to floats
                valid_amounts = []
                for amt in amounts:
                    try:
                        val = float(amt.replace(',', ''))
                        valid_amounts.append(val)
                    except:
                        pass
                
                if valid_amounts:
                    # Usually the first valid amount is the balance in the row
                    # (unless there are codes/ids, but typically those aren't formatted with decimals)
                    result["balances"][target] = valid_amounts[0]

except Exception as e:
    result["connection_error"] = True
    result["error_msg"] = str(e)

print(json.dumps(result))
EOF

# Run scraper
python3 /tmp/scrape_results.py > /tmp/scraped_data.json 2>/dev/null

# Prepare final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os

try:
    with open('/tmp/scraped_data.json') as f:
        data = json.load(f)
except:
    data = {}

output = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'screenshot_path': '/tmp/task_final.png',
    'scraped_data': data
}

print(json.dumps(output))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="