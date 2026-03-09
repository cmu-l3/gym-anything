#!/bin/bash
set -e
echo "=== Setting up Configure MyElectric App Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Emoncms
wait_for_emoncms

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Create required feeds with data if they don't exist
# We use a python script to ensure we get the IDs and put in some data
echo "Ensuring feeds exist and have data..."
cat > /tmp/setup_feeds.py << 'EOF'
import urllib.request, urllib.parse, json, time, sys, random

base_url = "http://localhost"
apikey = sys.argv[1]

def api(endpoint, params):
    url = f"{base_url}/{endpoint}?apikey={apikey}&" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url) as r:
            return json.loads(r.read().decode())
    except Exception as e:
        print(f"Error {endpoint}: {e}")
        return None

# Check/Create house_power
feeds = api("feed/list.json", {})
power_feed = next((f for f in feeds if f['name'] == 'house_power'), None)
if not power_feed:
    print("Creating house_power feed...")
    res = api("feed/create.json", {"name": "house_power", "tag": "House", "datatype": 1, "engine": 5, "options": '{"interval":10}', "unit": "W"})
    power_id = res['feedid']
else:
    power_id = power_feed['id']

# Check/Create house_energy_kwh
energy_feed = next((f for f in feeds if f['name'] == 'house_energy_kwh'), None)
if not energy_feed:
    print("Creating house_energy_kwh feed...")
    res = api("feed/create.json", {"name": "house_energy_kwh", "tag": "House", "datatype": 1, "engine": 5, "options": '{"interval":10}', "unit": "kWh"})
    energy_id = res['feedid']
else:
    energy_id = energy_feed['id']

# Insert some dummy data (last 2 hours)
now = int(time.time())
print(f"Injecting data into feeds {power_id} and {energy_id}...")
energy_accum = 100.0
for t in range(now - 7200, now, 10):
    power = 500 + random.randint(-100, 500)
    # Energy is power * time. 10s at X Watts. kWh = (W * 10/3600) / 1000
    energy_accum += (power * 10 / 3600.0) / 1000.0
    
    # Bulk insert is better but simple individual inserts work for setup
    # Actually, let's just do the last point to ensure current value exists
    pass

# Update last value
api("feed/insert.json", {"id": power_id, "time": now, "value": power})
api("feed/insert.json", {"id": energy_id, "time": now, "value": energy_accum})

print("Feeds ready.")
EOF

APIKEY_WRITE=$(get_apikey_write)
python3 /tmp/setup_feeds.py "$APIKEY_WRITE"

# 4. Clear existing MyElectric config (Anti-gaming)
echo "Clearing existing MyElectric configuration..."
db_query "DELETE FROM app_config WHERE app='myelectric'"

# 5. Launch Firefox to the Apps page
# We launch to the main app list so the agent has to find "My Electric"
echo "Launching Firefox..."
launch_firefox_to "http://localhost/app/view" 5

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="