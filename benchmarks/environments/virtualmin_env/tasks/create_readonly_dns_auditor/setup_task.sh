#!/bin/bash
echo "=== Setting up create_readonly_dns_auditor task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up: Remove dns_auditor if it already exists (idempotency/anti-gaming)
# We use direct file manipulation or webmin command if available, but simplest is via API or file edits.
# Webmin users are in /etc/webmin/miniserv.users and /etc/webmin/webmin.acl
if grep -q "^dns_auditor:" /etc/webmin/miniserv.users; then
    echo "Cleaning up previous dns_auditor user..."
    # Remove from users file
    grep -v "^dns_auditor:" /etc/webmin/miniserv.users > /tmp/users.tmp && mv /tmp/users.tmp /etc/webmin/miniserv.users
    # Remove from global ACL
    grep -v "^dns_auditor:" /etc/webmin/webmin.acl > /tmp/acl.tmp && mv /tmp/acl.tmp /etc/webmin/webmin.acl
    # Remove module specific ACL file
    rm -f /etc/webmin/bind8/dns_auditor.acl
    
    # Reload Webmin to apply changes
    /etc/webmin/reload >/dev/null 2>&1 || systemctl reload webmin
    echo "Cleanup complete."
fi

# 2. Ensure Virtualmin/Webmin is ready and logged in
ensure_virtualmin_ready
sleep 2

# 3. Navigate to the Webmin Users page to give the agent a starting point
# URL: https://localhost:10000/acl/index.cgi
navigate_to "https://localhost:10000/acl/index.cgi"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Starting state: Webmin Users page open. User 'dns_auditor' does not exist."