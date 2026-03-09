#!/bin/bash
set -e
echo "=== Setting up secure_sensitive_files task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure acmecorp.test domain exists (it should be pre-seeded, but verify)
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test..."
    virtualmin create-domain --domain acmecorp.test --pass "TempPass123!" --unix --dir --web --dns --mysql
fi

# 2. Plant Sensitive Data
DOC_ROOT="/home/acmecorp/public_html"

# Create .env file
echo "Creating vulnerable .env file..."
cat > "$DOC_ROOT/.env" << EOF
APP_ENV=production
APP_DEBUG=true
DB_HOST=localhost
DB_DATABASE=acme_production
DB_USERNAME=acme_user
DB_PASSWORD=SuperSecretPassword123!
API_KEY=sk_live_51Mz...
EOF

# Create .git directory structure
echo "Creating vulnerable .git directory..."
mkdir -p "$DOC_ROOT/.git/refs/heads"
mkdir -p "$DOC_ROOT/.git/objects"
echo "ref: refs/heads/main" > "$DOC_ROOT/.git/HEAD"
echo "test config" > "$DOC_ROOT/.git/config"

# Set permissions (User must own them, but they are world readable for the test)
chown -R acmecorp:acmecorp "$DOC_ROOT"
chmod 644 "$DOC_ROOT/.env"
chmod -R 755 "$DOC_ROOT/.git"

# 3. Ensure Apache is running and config is clean initially
# Reset config to default if needed (simple check)
CONF_FILE="/etc/apache2/sites-available/acmecorp.test.conf"
if grep -q "Require all denied" "$CONF_FILE"; then
    echo "WARNING: Cleanup previous run artifacts from Apache config..."
    # Naive cleanup: remove lines with denied (in a real scenario, we might restore a backup)
    # For now, we assume the env is fresh or clean enough.
    true 
fi
systemctl reload apache2

# 4. Verify initial vulnerability (Self-check)
echo "Verifying initial state (should be 200 OK)..."
# Resolve to local IP manually to ensure we hit the vhost
IP="127.0.0.1"
HTTP_CODE_ENV=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: acmecorp.test" "http://$IP/.env")
HTTP_CODE_GIT=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: acmecorp.test" "http://$IP/.git/HEAD")

if [ "$HTTP_CODE_ENV" != "200" ] || [ "$HTTP_CODE_GIT" != "200" ]; then
    echo "WARNING: Initial state check failed. .env: $HTTP_CODE_ENV, .git: $HTTP_CODE_GIT"
    # Proceed anyway, but log it
else
    echo "Initial state verified: Files are publicly accessible."
fi

# 5. Launch Firefox to the correct page
# Navigate to "Services > Configure Website" for acmecorp.test
# In Virtualmin, the "Edit Directives" page is often at:
# /virtual-server/edit_directives.cgi?dom=ID
DOMAIN_ID=$(get_domain_id "acmecorp.test")

ensure_virtualmin_ready
navigate_to "https://localhost:10000/virtual-server/edit_directives.cgi?dom=${DOMAIN_ID}"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="