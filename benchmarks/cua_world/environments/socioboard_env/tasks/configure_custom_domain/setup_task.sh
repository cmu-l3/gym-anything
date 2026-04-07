#!/bin/bash
echo "=== Setting up configure_custom_domain task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (must create vhost AFTER this)
date +%s > /tmp/task_start_time.txt

# Ensure clean initial state: remove any existing configuration for the domain
echo "Cleaning up any pre-existing configurations..."
rm -f /etc/apache2/sites-enabled/social-agency.conf 2>/dev/null || true
rm -f /etc/apache2/sites-available/social-agency.conf 2>/dev/null || true
sed -i '/social\.agency\.local/d' /etc/hosts 2>/dev/null || true

# Restore default APP_URL just in case
sed -i 's|^APP_URL=.*|APP_URL=http://localhost|g' /opt/socioboard/socioboard-web-php/.env 2>/dev/null || true

# Reload Apache to clear state
systemctl reload apache2 2>/dev/null || true

# Verify Socioboard is currently working on localhost
if ! wait_for_http "http://localhost/" 60; then
    echo "WARNING: Socioboard not reachable at http://localhost/ during setup"
fi

# Ensure Firefox is open to the default localhost page
ensure_firefox_running "http://localhost/"
sleep 3

# Take initial screenshot showing standard localhost view
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="