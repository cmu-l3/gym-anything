#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_extra_admin task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean State: Ensure the extra admin doesn't already exist
# We want the agent to actually create it, not just find an existing one.
if virtualmin list-admins --domain acmecorp.test --name devops_carter >/dev/null 2>&1; then
    echo "Cleaning up existing admin devops_carter..."
    virtualmin delete-admin --domain acmecorp.test --name devops_carter >/dev/null 2>&1 || true
fi

# 3. Record initial state of admins (to prove it didn't exist)
virtualmin list-admins --domain acmecorp.test --name-only > /tmp/initial_admins_list.txt 2>/dev/null || echo "" > /tmp/initial_admins_list.txt

# 4. Ensure Virtualmin services are running
for svc in apache2 mariadb named webmin; do
    systemctl is-active --quiet "$svc" || systemctl start "$svc" 2>/dev/null || true
done
sleep 2

# 5. Ensure Firefox is open and logged into Virtualmin
ensure_virtualmin_ready

# 6. Navigate to the acmecorp.test domain summary to give the agent a good starting point
# We need the domain ID for the URL in Virtualmin 8.x/GPL
DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/summary_domain.cgi?dom=${DOMAIN_ID}"
else
    # Fallback to index if domain not found (though environment should have it)
    navigate_to "https://localhost:10000/virtual-server/index.cgi"
fi
sleep 5

# 7. Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="