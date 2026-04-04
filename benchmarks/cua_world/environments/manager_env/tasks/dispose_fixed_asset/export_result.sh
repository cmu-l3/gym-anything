#!/bin/bash
# Export script for dispose_fixed_asset
# Fetches the state of the specific asset to verify disposal details

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch the asset state using the saved Business Key and Asset UUID
python3 -c '
import requests
import sys
import json
import os
import re

BASE_URL = "http://localhost:8080"
OUTPUT_FILE = "/tmp/task_result.json"

def main():
    # Load keys
    try:
        with open("/tmp/biz_key.txt", "r") as f:
            biz_key = f.read().strip()
        with open("/tmp/asset_uuid.txt", "r") as f:
            asset_uuid = f.read().strip()
    except FileNotFoundError:
        # Fallback: Create empty result if setup failed/files missing
        save_result(False, {}, "Missing setup keys")
        return

    # Login to establish session
    s = requests.Session()
    s.post(f"{BASE_URL}/login", data={"Username": "administrator"})
    
    # Fetch the specific asset form (this contains the data)
    # URL pattern: /fixed-asset-form?Key={UUID}&FileID={BIZ_KEY}
    # Note: Manager URLs can vary, constructing carefuly
    url = f"{BASE_URL}/fixed-asset-form?Key={asset_uuid}&FileID={biz_key}"
    resp = s.get(url)
    
    if resp.status_code != 200:
        save_result(False, {}, f"Failed to fetch asset: HTTP {resp.status_code}")
        return

    # Extract the JSON data object embedded in the page
    # Look for: <input type="hidden" name="..." value="{JSON_DATA}" />
    # The value is HTML-escaped, so we need to handle that.
    # Pattern: value="{&quot;Name&quot;:&quot;Ford Transit 2018&quot;...}"
    
    match = re.search(r"value=\"({.*?})\"", resp.text)
    if not match:
        save_result(False, {}, "Could not parse asset data from page")
        return
        
    raw_json = match.group(1).replace("&quot;", "\"")
    
    try:
        data = json.loads(raw_json)
    except json.JSONDecodeError:
        save_result(False, {}, "Failed to decode asset JSON")
        return
        
    # Check "Disposed" status
    # In Manager, checking the box usually adds "DisposalDate", "DisposalAmount", "DisposalAccount" keys 
    # OR sets a boolean "Disposed": true
    # Let verify what we found.
    
    result = {
        "asset_found": True,
        "data": data,
        "is_disposed": data.get("Disposed", False),
        "disposal_date": data.get("DisposalDate", ""),
        "disposal_amount": data.get("DisposalAmount", 0),
        "disposal_account": data.get("DisposalAccount", "")
    }
    
    save_result(True, result, "Asset data retrieved")

def save_result(success, data, message):
    output = {
        "success": success,
        "message": message,
        "task_start": int(os.environ.get("TASK_START", 0)),
        "task_end": int(os.environ.get("TASK_END", 0)),
        "screenshot_path": "/tmp/task_final.png",
        **data
    }
    with open(OUTPUT_FILE, "w") as f:
        json.dump(output, f, indent=2)

if __name__ == "__main__":
    os.environ["TASK_START"] = sys.argv[1]
    os.environ["TASK_END"] = sys.argv[2]
    main()
' "$TASK_START" "$TASK_END"

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="