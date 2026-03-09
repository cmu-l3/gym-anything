#!/bin/bash
set -e
echo "=== Setting up task: create_delegated_command ==="

# Source standard utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create a dummy systemd service for the agent to restart
echo "--- Creating dummy service acmecorp-worker ---"
cat > /etc/systemd/system/acmecorp-worker.service << 'EOF'
[Unit]
Description=Acme Corp Backend Worker
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c "while true; do echo 'Worker running...'; sleep 60; done"
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable acmecorp-worker
systemctl start acmecorp-worker

# 2. Ensure the acmecorp.test domain exists
if ! virtualmin list-domains --name-only | grep -q "^acmecorp.test$"; then
    echo "Creating acmecorp.test..."
    virtualmin create-domain --domain acmecorp.test --pass "GymAnything123!" --unix --dir --webmin --web --dns --mail --mysql
fi

# 3. Ensure acmecorp user exists (should be created by create-domain, but double check)
if ! grep -q "^acmecorp:" /etc/passwd; then
    echo "ERROR: acmecorp user not found even after domain creation."
    exit 1
fi

# 4. Record initial ACL state (to prove it changed later)
grep "^acmecorp:" /etc/webmin/webmin.acl > /tmp/initial_acl.txt || echo "acmecorp: virtual-server" > /tmp/initial_acl.txt

# 5. Launch Firefox and login to Virtualmin
ensure_virtualmin_ready

# 6. Navigate to Webmin Users or Virtualmin Users page to give a hint of where to start
# We'll just leave them at the dashboard, but ensure window is maximized
focus_firefox

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="