#!/bin/bash
set -e
echo "=== Setting up DNS Zone Parameters Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure acmecorp.test domain exists with DNS
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "ERROR: acmecorp.test domain does not exist!"
    exit 1
fi

# Verify DNS is enabled for the domain
if ! virtualmin list-domains --domain acmecorp.test --multiline 2>/dev/null | grep -q "DNS domain: Yes"; then
    echo "ERROR: DNS is not enabled for acmecorp.test!"
    exit 1
fi

# Record initial zone file state for anti-gaming verification
echo "--- Recording initial DNS zone state ---"
# Find the zone file (location varies by distro/config, usually /var/lib/bind)
ZONE_FILE=$(find /var/lib/bind /etc/bind -name "acmecorp.test.hosts" -o -name "acmecorp.test.db" 2>/dev/null | head -1)

if [ -n "$ZONE_FILE" ]; then
    echo "Found zone file: $ZONE_FILE"
    cp "$ZONE_FILE" /tmp/initial_zone_file.txt
    sha256sum "$ZONE_FILE" > /tmp/initial_zone_hash.txt
    echo "$ZONE_FILE" > /tmp/zone_file_path.txt
else
    echo "WARNING: Could not find zone file! Verification may be limited."
fi

# Ensure services are running
systemctl is-active --quiet named 2>/dev/null || systemctl start named 2>/dev/null || true
systemctl is-active --quiet bind9 2>/dev/null || systemctl start bind9 2>/dev/null || true

# Ensure Firefox is open and logged in to Virtualmin
ensure_virtualmin_ready

# Navigate to Virtualmin DNS Records page for acmecorp.test
# This puts the agent in the right context
DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/list_records.cgi?dom=${DOMAIN_ID}"
else
    navigate_to "https://localhost:10000/virtual-server/index.cgi?domain=acmecorp.test"
fi
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="