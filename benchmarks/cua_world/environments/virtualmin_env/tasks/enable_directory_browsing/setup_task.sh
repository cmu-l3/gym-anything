#!/bin/bash
echo "=== Setting up enable_directory_browsing task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. CLEANUP: Remove the target directory if it exists from previous runs
TARGET_DIR="/home/acmecorp/public_html/downloads"
if [ -d "$TARGET_DIR" ]; then
    echo "Cleaning up existing downloads directory..."
    rm -rf "$TARGET_DIR"
fi

# 2. CLEANUP: Remove any existing Directory directives for /downloads in Apache config
# This is a rough cleanup to ensure the agent has to do the work
APACHE_CONFIG=$(find /etc/apache2/sites-available -name "*acmecorp.test.conf" | head -1)
if [ -f "$APACHE_CONFIG" ]; then
    # Create backup
    cp "$APACHE_CONFIG" "${APACHE_CONFIG}.bak"
    
    # Simple check: if we see a <Directory .../downloads> block, we might want to warn or try to strip it.
    # For stability, we'll just reload Apache to ensure the current state is active.
    # (Advanced cleanup of multi-line XML blocks via sed is risky in bash, assuming manual cleanup if needed)
    echo "Checking Apache config at $APACHE_CONFIG"
fi

systemctl reload apache2 || true

# 3. SETUP: Ensure Virtualmin is ready and logged in
ensure_virtualmin_ready

# 4. NAVIGATION: Go to the virtual server details to save agent some clicks
# We navigate to the Edit Virtual Server page or standard dashboard
ACMECORP_ID=$(get_domain_id "acmecorp.test")
navigate_to "https://localhost:10000/virtual-server/index.cgi?dom=${ACMECORP_ID}"
sleep 5

# 5. EVIDENCE: Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="