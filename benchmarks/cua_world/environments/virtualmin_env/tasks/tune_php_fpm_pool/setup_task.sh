#!/bin/bash
set -e
echo "=== Setting up tune_php_fpm_pool task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure acmecorp.test exists (should be created by env setup, but double check)
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test..."
    # We use the helper logic or just fail if env is broken, but let's try to create minimal
    virtualmin create-domain --domain acmecorp.test --pass "TempPass123!" --unix --dir --web --dns --mysql
fi

# Get Domain ID to locate the correct pool file
DOM_ID=$(get_domain_id "acmecorp.test")
echo "Domain ID for acmecorp.test: $DOM_ID"

# Locate the PHP-FPM pool configuration file
# It typically lives in /etc/php/*/fpm/pool.d/$DOM_ID.conf
POOL_FILE=$(find /etc/php -name "${DOM_ID}.conf" | grep "fpm/pool.d" | head -n 1)

if [ -z "$POOL_FILE" ]; then
    echo "ERROR: Could not find PHP-FPM pool file for domain ID $DOM_ID"
    # Fallback search by name if ID-based file doesn't exist (older Virtualmin versions)
    POOL_FILE=$(find /etc/php -name "acmecorp.conf" | grep "fpm/pool.d" | head -n 1)
fi

if [ -z "$POOL_FILE" ]; then
    echo "CRITICAL: PHP-FPM pool file not found. Ensure PHP-FPM is enabled for this domain."
    # Try to enable it
    virtualmin modify-web --domain acmecorp.test --mode fpm
    sleep 5
    POOL_FILE=$(find /etc/php -name "${DOM_ID}.conf" | grep "fpm/pool.d" | head -n 1)
fi

echo "Target Pool File: $POOL_FILE"
echo "$POOL_FILE" > /tmp/target_pool_file.txt

# Reset the pool file to "bad" defaults to ensure the agent actually does work
# We use sed to safely replace existing values or append if missing
echo "Resetting configuration to default/bad values..."
if [ -f "$POOL_FILE" ]; then
    # Create backup
    cp "$POOL_FILE" "${POOL_FILE}.bak"
    
    # Simple reset strategy: Set values to standard defaults
    # We use a python script for robust INI manipulation
    python3 -c "
import sys
import re

file_path = '$POOL_FILE'
with open(file_path, 'r') as f:
    content = f.read()

# Replacements
replacements = {
    r'^\s*pm\s*=\s*.*': 'pm = dynamic',
    r'^\s*pm.max_children\s*=\s*.*': 'pm.max_children = 5',
    r'^\s*pm.start_servers\s*=\s*.*': 'pm.start_servers = 1',
    r'^\s*pm.min_spare_servers\s*=\s*.*': 'pm.min_spare_servers = 1',
    r'^\s*pm.max_spare_servers\s*=\s*.*': 'pm.max_spare_servers = 3'
}

for pattern, repl in replacements.items():
    if re.search(pattern, content, re.MULTILINE):
        content = re.sub(pattern, repl, content, flags=re.MULTILINE)
    else:
        # If not found, we might need to append, but usually these exist in default templates.
        # For simplicity in setup, we assume they exist or the agent will add them.
        pass

with open(file_path, 'w') as f:
    f.write(content)
"
fi

# Reload PHP-FPM to apply bad defaults
systemctl reload php*-fpm || true

# Save initial state checksum
md5sum "$POOL_FILE" > /tmp/initial_pool_checksum.txt

# Launch Firefox and log in
ensure_virtualmin_ready

# Navigate to the specific domain's page to save agent some clicks (optional, but helpful)
# We navigate to the Edit Virtual Server page as a starting point
navigate_to "https://localhost:10000/virtual-server/edit_domain.cgi?dom=${DOM_ID}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="