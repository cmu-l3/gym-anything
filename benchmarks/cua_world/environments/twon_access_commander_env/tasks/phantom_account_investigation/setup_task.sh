#!/bin/bash
echo "=== Setting up Phantom Account Investigation task ==="
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

wait_for_ac_demo
ac_login

# Clean up any existing phantom accounts from previous runs
echo "Cleaning up prior phantom accounts..."
EXISTING=$(ac_api GET "/users" | jq -r '.[] | select(.email != null and (.email | contains("@external-vendor.net"))) | .id' 2>/dev/null)
for uid in $EXISTING; do
    ac_api DELETE "/users/$uid" > /dev/null 2>&1 && echo "Deleted prior phantom account (id=$uid)" || true
done

# Remove any previous compromised card file
rm -f /home/ga/compromised_card.txt 2>/dev/null || true

# Generate a highly randomized 10-digit card number (anti-gaming mechanism)
RANDOM_CARD=$(cat /dev/urandom | tr -dc '0-9' | fold -w 10 | head -n 1)

# Save ground truth securely (hidden from agent)
sudo mkdir -p /var/lib/app/ground_truth
echo "$RANDOM_CARD" | sudo tee /var/lib/app/ground_truth/phantom_card.txt > /dev/null
sudo chmod 700 /var/lib/app/ground_truth
sudo chmod 600 /var/lib/app/ground_truth/phantom_card.txt

echo "Injecting phantom user with random card..."
# Use Python for reliable JSON payload injection
cat << 'EOF' > /tmp/inject_phantom.py
import sys
import requests
import urllib3
urllib3.disable_warnings()

card_num = sys.argv[1]
s = requests.Session()
s.verify = False

# Login
auth = s.put("https://localhost:9443/api/v3/auth", json={"login": "admin", "password": "2n"})
if auth.status_code not in (200, 201):
    print("Login failed")
    sys.exit(1)

# Create phantom user
phantom = {
    "firstName": "Alex",
    "lastName": "Ghost",
    "email": "admin@external-vendor.net",
    "company": "External Maintenance",
    "cardNumber": card_num,
    "enabled": True
}
res = s.post("https://localhost:9443/api/v3/users", json=phantom)
print(f"Injection status: {res.status_code}")
EOF

python3 /tmp/inject_phantom.py "$RANDOM_CARD"

# Launch Firefox directly to the Users page
launch_firefox_to "${AC_URL}/#/users" 8

# Take initial state screenshot
take_screenshot /tmp/task_phantom_start.png

echo "=== Task Setup Complete ==="