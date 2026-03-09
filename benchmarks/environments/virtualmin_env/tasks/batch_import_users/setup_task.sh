#!/bin/bash
set -e
echo "=== Setting up task: batch_import_users@1 ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Virtualmin is ready & Firefox is open
ensure_virtualmin_ready

# 2. Ensure acmecorp.test domain exists (recreate if missing)
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test..."
    # Create with default features
    virtualmin create-domain \
        --domain acmecorp.test \
        --pass "AcmeCorp123!" \
        --unix --dir --webmin --web --dns --mail --mysql \
        > /dev/null 2>&1
fi

# 3. Clean up any pre-existing task users (idempotency)
echo "Cleaning up potential stale users..."
STALE_USERS=("dave.bowman" "frank.poole" "hal.9000")
for user in "${STALE_USERS[@]}"; do
    # Check if user exists fully qualified or just username
    if virtualmin list-users --domain acmecorp.test --name-only | grep -q "^${user}"; then
        virtualmin delete-user --domain acmecorp.test --user "$user" > /dev/null 2>&1 || true
    fi
done

# 4. Create the CSV file with real data
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/new_hires.csv << 'EOF'
email,realname,password
dave.bowman@acmecorp.test,David Bowman,Jupiter2001!
frank.poole@acmecorp.test,Frank Poole,DiscoveryOne!
hal.9000@acmecorp.test,HAL 9000,CantDoThatDave!
EOF
chmod 644 /home/ga/Documents/new_hires.csv
chown ga:ga /home/ga/Documents/new_hires.csv

echo "CSV file created at /home/ga/Documents/new_hires.csv"

# 5. Record initial user count for verification
INITIAL_COUNT=$(virtualmin list-users --domain acmecorp.test --name-only | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_user_count.txt

# 6. Navigate Firefox to the Edit Users page for acmecorp.test to assist start
#    (We use the ID-based URL for robustness with Virtualmin 7/8)
DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "${VIRTUALMIN_URL}/virtual-server/list_users.cgi?dom=${DOMAIN_ID}"
fi
sleep 2

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="