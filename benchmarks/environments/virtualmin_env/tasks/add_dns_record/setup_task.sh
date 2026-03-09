#!/bin/bash
echo "=== Setting up add_dns_record task ==="

source /workspace/scripts/task_utils.sh

# Remove the blog CNAME if it already exists from a previous run
if virtualmin get-dns --domain acmecorp.test 2>/dev/null | grep -q "blog.*CNAME"; then
    echo "WARNING: blog CNAME already exists, removing it..."
    # Use Virtualmin CLI to remove the specific DNS record
    # The modify-dns command can remove records
    virtualmin modify-dns \
        --domain acmecorp.test \
        --remove-record "blog CNAME acmecorp.test." 2>&1 | tail -3 || true
    sleep 2
fi

# Ensure Virtualmin is accessible in Firefox
ensure_virtualmin_ready
sleep 2

# Navigate to the DNS Records page for acmecorp.test
# list_records.cgi is the correct Virtualmin 8.x name; uses numeric domain ID
ACMECORP_ID=$(get_domain_id "acmecorp.test")
navigate_to "https://localhost:10000/virtual-server/list_records.cgi?dom=${ACMECORP_ID}"
sleep 5

take_screenshot /tmp/add_dns_record_start.png
echo "=== add_dns_record task setup complete ==="
echo "Agent should see the DNS Records page for acmecorp.test in Firefox."
