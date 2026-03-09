#!/bin/bash
set -e
echo "=== Setting up install_wordpress_script task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. ensure domain exists (acmecorp.test is pre-seeded, but verify)
if ! virtualmin list-domains --name-only | grep -q "^acmecorp.test$"; then
    echo "Creating acmecorp.test..."
    virtualmin create-domain --domain acmecorp.test --pass "AcmeCorp123!" --unix --dir --webmin --web --dns --mail --mysql
fi

# 3. Clean state: Remove any existing WordPress installations on this domain
echo "Cleaning up existing WordPress installations..."
# List scripts returns ID in the first column usually, but format varies. 
# Simplest is to check if installed and delete by ID if possible, or just nuke the dir and db.
INSTALLED_SCRIPTS=$(virtualmin list-scripts --domain acmecorp.test --multiline 2>/dev/null || true)

if echo "$INSTALLED_SCRIPTS" | grep -qi "wordpress"; then
    # Try to extract ID and delete. The output format is complex, so we might just use the CLI to uninstall all if possible
    # Or just uninstall the specific path if we knew it.
    # Since we can't easily parse the ID in bash reliably without complex logic, 
    # we will manually clean up the artifacts which allows a fresh install to proceed.
    
    # Remove files
    rm -rf /home/acmecorp/public_html/blog
    rm -rf /home/acmecorp/public_html/wordpress
    
    # Drop likely databases
    mysql -u root -pGymAnything123! -e "DROP DATABASE IF EXISTS acmecorp_wordpress;" 2>/dev/null || true
    mysql -u root -pGymAnything123! -e "DROP DATABASE IF EXISTS acmecorp_wp;" 2>/dev/null || true
    
    # Force removal from Virtualmin's knowledge base (dangerous but effective for reset)
    # Ideally we use delete-script, but we'll rely on file/db cleanup permitting a new install.
    echo "Manual cleanup performed."
fi

# Record initial script count
INITIAL_COUNT=$(virtualmin list-scripts --domain acmecorp.test 2>/dev/null | grep -c "WordPress" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_script_count.txt

# 4. Prepare GUI
ensure_virtualmin_ready

# Navigate specifically to the Install Scripts page for acmecorp.test
DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/list_scripts.cgi?dom=${DOMAIN_ID}"
else
    # Fallback to main page if ID fails
    navigate_to "https://localhost:10000/"
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="