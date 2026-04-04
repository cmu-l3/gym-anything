#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Data from Manager.io API
# We need to export:
# - Chart of Accounts (to check if "Bad Debts" exists)
# - Credit Notes (to find the transaction)
# - The specific Credit Note details (to check allocation)

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"
BIZ_KEY=$(cat /tmp/biz_key.txt 2>/dev/null)

if [ -z "$BIZ_KEY" ]; then
    # Emergency recovery of key
    BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
    BIZ_KEY=$(echo "$BIZ_PAGE" | grep -oP 'start\?\K[^"]+(?="[^>]*>Northwind Traders)' | head -1)
fi

# Login again to ensure session
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

echo "Exporting Manager.io data..."

# Export P&L Accounts (Expenses are here)
# Manager stores accounts in various internal objects. We'll dump the main endpoints.
# Note: Manager.io's API structure can vary, but usually exposes objects via UUID endpoints.
# We will use the generic 'backup' approach or targeted JSON endpoints if available.
# Since we are essentially "root", we can iterate known endpoints.

# Helper python script to fetch and combine data
python3 -c "
import requests
import json
import sys

s = requests.Session()
s.cookies.load(ignore_discard=True, ignore_expires=True, filename='$COOKIE_FILE')
base_url = '$MANAGER_URL'
biz_key = '$BIZ_KEY'

def get_json(endpoint):
    try:
        # Try RESTful-like API pattern common in Manager extensions or use internal API
        # Manager API is often /api/{biz_key}/{object_type}.json
        resp = s.get(f'{base_url}/api/{biz_key}/{endpoint}.json')
        if resp.status_code == 200:
            return resp.json()
        return []
    except:
        return []

data = {}

# 1. Fetch Accounts (Chart of Accounts)
# Endpoints might be 'accounts', 'chart-of-accounts', 'profit-and-loss-statement-accounts'
data['accounts'] = get_json('accounts') 
if not data['accounts']:
    # Fallback: try to deduce from expense-claims or similar if specific endpoint hidden
    # For now, we assume standard API access enabled in this environment
    pass

# 2. Fetch Credit Notes
data['credit_notes'] = get_json('credit-notes')

# 3. Fetch Customers (to link name to UUID)
data['customers'] = get_json('customers')

# 4. Fetch specific details if needed (nested lines usually in the main object)

print(json.dumps(data, indent=2))
" > /tmp/manager_data_dump.json 2>/dev/null

# If Python script failed or API is locked down, we might need a fallback.
# Assuming environment allows API access as per setup_data.sh usage.

# Validate capture
if [ ! -s /tmp/manager_data_dump.json ]; then
    echo "{}" > /tmp/manager_data_dump.json
fi

# 3. Create Final Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end": $(date +%s),
    "screenshot_path": "/tmp/task_final.png",
    "manager_data": $(cat /tmp/manager_data_dump.json)
}
EOF

# Permissions
chmod 666 /tmp/task_result.json

echo "Export complete."