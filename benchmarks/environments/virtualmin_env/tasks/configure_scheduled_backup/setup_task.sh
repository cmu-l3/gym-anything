#!/bin/bash
set -e
echo "=== Setting up scheduled backup task ==="

source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Record Start Time (Anti-gaming)
# ---------------------------------------------------------------
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 2. Prepare Backup Destination
# ---------------------------------------------------------------
echo "--- Creating /backup/nightly directory ---"
mkdir -p /backup/nightly
chmod 755 /backup
chmod 755 /backup/nightly
chown root:root /backup/nightly

# ---------------------------------------------------------------
# 3. Clean State: Remove existing scheduled backups
# ---------------------------------------------------------------
BACKUP_CONFIG_DIR="/etc/webmin/virtual-server/backups"
if [ -d "$BACKUP_CONFIG_DIR" ]; then
    echo "--- Cleaning existing scheduled backups ---"
    # Remove numbered config files (Virtualmin stores them as integers like '1', '2')
    find "$BACKUP_CONFIG_DIR" -maxdepth 1 -type f -regex '.*/[0-9]+' -delete 2>/dev/null || true
    # Remove metadata files
    rm -f "$BACKUP_CONFIG_DIR"/*.backup 2>/dev/null || true
fi
# Create dir if it doesn't exist
mkdir -p "$BACKUP_CONFIG_DIR"

# ---------------------------------------------------------------
# 4. Ensure Target Domains Exist
# ---------------------------------------------------------------
echo "--- Verifying domains ---"
# We need these domains to exist so the agent can select them
for domain in acmecorp.test nonprofitaid.test globalshop.test; do
    if ! virtualmin_domain_exists "$domain"; then
        echo "Creating missing domain: $domain"
        virtualmin create-domain --domain "$domain" --pass "TempPass123!" --unix --dir --webmin --web --dns --mail --mysql >/dev/null 2>&1
    fi
done

# ---------------------------------------------------------------
# 5. Launch Application (Firefox -> Virtualmin)
# ---------------------------------------------------------------
ensure_virtualmin_ready

# Navigate to the Backup and Restore main page to help the agent start
echo "Navigating to Backup menu..."
navigate_to "${VIRTUALMIN_URL}/virtual-server/index.cgi"
sleep 5

# Open the Backup and Restore menu category (simulated by just ensuring we are on dashboard)
# The agent needs to find "Scheduled Backups"

# ---------------------------------------------------------------
# 6. Initial Evidence
# ---------------------------------------------------------------
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="