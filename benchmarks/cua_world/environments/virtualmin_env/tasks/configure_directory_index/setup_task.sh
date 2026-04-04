#!/bin/bash
set -e
echo "=== Setting up configure_directory_index task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Services are running
systemctl start apache2 2>/dev/null || true
systemctl start webmin 2>/dev/null || true

# 2. Setup the Domain 'acmecorp.test'
if ! virtualmin list-domains --name-only | grep -q "^acmecorp.test$"; then
    echo "Creating acmecorp.test..."
    virtualmin create-domain --domain acmecorp.test --pass GymAnything123! --unix --dir --web --dns --mysql
fi

DOCROOT="/home/acmecorp/public_html"
CONF_FILE="/etc/apache2/sites-available/acmecorp.test.conf"

# 3. Create Content
# promo.html (The goal)
cat > "$DOCROOT/promo.html" <<EOF
<!DOCTYPE html>
<html>
<body>
    <h1>Something Big is Coming</h1>
    <p>PROMO_2024_LAUNCH</p>
</body>
</html>
EOF
chown acmecorp:acmecorp "$DOCROOT/promo.html"

# index.php (The current default)
cat > "$DOCROOT/index.php" <<EOF
<?php echo 'Old Home Page'; ?>
EOF
chown acmecorp:acmecorp "$DOCROOT/index.php"

# assets directory (For testing directory listing)
mkdir -p "$DOCROOT/assets"
touch "$DOCROOT/assets/logo.png"
chown -R acmecorp:acmecorp "$DOCROOT/assets"

# 4. Set BAD Initial State (Explicitly Insecure/Wrong)
echo "Setting initial bad state..."

# Ensure DirectoryIndex puts index.php first
if grep -q "DirectoryIndex" "$CONF_FILE"; then
    sed -i 's/DirectoryIndex.*/DirectoryIndex index.php index.cgi index.html/' "$CONF_FILE"
else
    # Fallback if directive missing (insert into VirtualHost)
    sed -i '/<VirtualHost/a \ \ \ \ DirectoryIndex index.php index.cgi index.html' "$CONF_FILE"
fi

# Ensure Options +Indexes (Directory listing ENABLED)
# We look for the Options line inside the public_html Directory block
# This is a bit complex with sed, so we'll use a specific replace if standard Virtualmin format exists
# Standard Virtualmin: Options -Indexes +IncludesNOEXEC +SymLinksIfOwnerMatch
sed -i 's/Options -Indexes/Options +Indexes/' "$CONF_FILE"

# Apply changes
systemctl reload apache2

# 5. Capture Initial State Screenshot
ensure_virtualmin_ready
# Navigate to Website Options for acmecorp.test to save the agent a click (optional, but good for context)
# We'll just leave them at the main page
navigate_to "https://localhost:10000/virtual-server/index.cgi"
sleep 2

take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="