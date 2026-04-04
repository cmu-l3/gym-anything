#!/bin/bash
# pre_task: Set up the create_admin_group task

echo "=== Setting up create_admin_group task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# 2. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Clean state: Ensure the group does not already exist in LDAP
echo "Ensuring clean state (removing target group if exists)..."
# We use kubectl to execute samba-tool inside the LDAP pod
kubectl exec -n arkcase arkcase-ldap-0 -- samba-tool group delete "FOIA_Senior_Analysts" 2>/dev/null || true

# 4. Record initial group count
INITIAL_COUNT=$(kubectl exec -n arkcase arkcase-ldap-0 -- samba-tool group list 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_group_count.txt

# 5. Prepare Firefox
# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
sleep 2
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Launch Firefox on ArkCase login page
echo "Launching Firefox..."
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"

# Handle SSL warning if it appears
handle_ssl_warning

# Focus and maximize
focus_firefox
maximize_firefox

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Agent must log in, go to Admin > Groups, and create 'FOIA_Senior_Analysts'"