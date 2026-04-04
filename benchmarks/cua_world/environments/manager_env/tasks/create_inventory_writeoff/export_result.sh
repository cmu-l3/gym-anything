#!/bin/bash
set -e

echo "=== Exporting Inventory Write-off Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Python script to scrape current state and export details
cat > /tmp/export_writeoff_data.py << 'PYEOF'
import requests
import re
import json
import sys
import os
from bs4 import BeautifulSoup

BASE_URL = "http://localhost:8080"
SESSION = requests.Session()

def get_business_key():
    SESSION.post(f"{BASE_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    resp = SESSION.get(f"{BASE_URL}/businesses")
    match = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', resp.text)
    if not match:
        match = re.search(r'start\?([^"&\s]+)', resp.text)
    return match.group(1) if match else None

def parse_write_off(url):
    """Visit a write-off detail page and parse fields."""
    resp = SESSION.get(url)
    html = resp.text
    soup = BeautifulSoup(html, 'html.parser')
    
    # Manager.io usually displays data in view mode as text or inputs
    # We look for the JSON blob often embedded in edit forms, OR parse the view table.
    # Parsing the VIEW page is safer for verification.
    
    data = {}
    
    # Date (usually in a specific div or table cell)
    # Strategy: Look for the text content near labels or within the main view container
    text_content = soup.get_text()
    
    # Try to find the Edit button to get the JSON object? 
    # Actually, simpler: Go to the EDIT page for this ID, it has the JSON object in the input value!
    edit_url = url.replace("/view?", "/inventory-write-off-form?")
    edit_resp = SESSION.get(edit_url)
    
    # Extract the big JSON object from value="{...}"
    json_match = re.search(r'value="({.*})"', edit_resp.text)
    if json_match:
        try:
            # HTML decode the quote marks
            json_str = json_match.group(1).replace('&quot;', '"')
            data = json.loads(json_str)
            return data
        except:
            pass
            
    return {}

def main():
    key = get_business_key()
    if not key:
        print("Error: No business key")
        sys.exit(1)

    # List all write-offs
    list_url = f"{BASE_URL}/inventory-write-offs?{key}"
    resp = SESSION.get(list_url)
    soup = BeautifulSoup(resp.text, 'html.parser')
    
    # Find all links to view write-offs
    # They look like <a href="view?key=...&FileID=...">
    links = []
    for a in soup.find_all('a', href=True):
        if 'inventory-write-off-view?' in a['href'] or ('view?' in a['href'] and 'FileID' in a['href']):
            full_url = f"{BASE_URL}/{a['href']}" if a['href'].startswith('inventory') or a['href'].startswith('view') else f"{BASE_URL}{a['href']}"
            links.append(full_url)
            
    # Filter unique links
    links = list(set(links))
    
    results = []
    for link in links:
        data = parse_write_off(link)
        if data:
            results.append(data)
            
    # Load initial count
    initial_count = 0
    if os.path.exists("/tmp/initial_writeoff_count.txt"):
        with open("/tmp/initial_writeoff_count.txt") as f:
            initial_count = int(f.read().strip())

    output = {
        "initial_count": initial_count,
        "final_count": len(results),
        "write_offs": results,
        "screenshot_path": "/tmp/task_final.png"
    }
    
    with open("/tmp/task_result.json", "w") as f:
        json.dump(output, f, indent=2)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # Fallback empty result
        with open("/tmp/task_result.json", "w") as f:
            json.dump({"error": str(e)}, f)
PYEOF

python3 /tmp/export_writeoff_data.py
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json