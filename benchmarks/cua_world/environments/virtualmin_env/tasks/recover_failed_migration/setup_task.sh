#!/bin/bash
# =============================================================================
# Setup: recover_failed_migration
#
# Creates a working acmecorp.test domain (website + DB + email), then
# introduces four realistic post-migration breakages:
#   1. PHP-FPM pool listen changed to TCP (Apache still expects Unix socket)
#   2. db_config.php owned by root with wrong MySQL password
#   3. Postfix transport map routes domain mail to a dead relay
#   4. DKIM / SPF / DMARC not configured (clean slate for agent to set up)
# =============================================================================

echo "=== Setting up recover_failed_migration task ==="

source /workspace/scripts/task_utils.sh

# Ensure mailutils and opendkim are available
which mail &>/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y mailutils &>/dev/null
which opendkim &>/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y opendkim opendkim-tools &>/dev/null || true

# Fallback definitions in case task_utils.sh is incomplete
if ! type json_escape &>/dev/null; then
    json_escape() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\n'/\\n}"
        echo "$s"
    }
fi

# ---------------------------------------------------------------
# 1. Clean stale outputs and record task start timestamp
# ---------------------------------------------------------------
rm -f /tmp/task_result.json /tmp/task_final.png /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/initial_checksums.txt /tmp/original_socket_path.txt 2>/dev/null || true

date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# ---------------------------------------------------------------
# 2. Ensure acmecorp.test domain exists
# ---------------------------------------------------------------
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "ERROR: acmecorp.test domain does not exist. Environment may not be set up correctly."
    exit 1
fi

echo "Domain acmecorp.test confirmed."

# Ensure acmecorp.test resolves locally (for browser and curl testing)
if ! grep -q "acmecorp.test" /etc/hosts; then
    echo "127.0.0.1 acmecorp.test" >> /etc/hosts
fi

# Ensure Maildir ownership matches the Virtualmin mail users (not just the domain user)
# Virtualmin creates users like info@acmecorp.test with their own UID
for MAILUSER in admin info sales support; do
    MAILUSER_FULL="${MAILUSER}@acmecorp.test"
    MAILUSER_UID=$(id -u "$MAILUSER_FULL" 2>/dev/null)
    MAILDIR="/home/acmecorp/homes/${MAILUSER}/Maildir"
    if [ -n "$MAILUSER_UID" ] && [ -d "$MAILDIR" ]; then
        chown -R "$MAILUSER_FULL":acmecorp "$MAILDIR" 2>/dev/null || true
    fi
    # Ensure home dir is accessible
    HOME_DIR="/home/acmecorp/homes/${MAILUSER}"
    if [ -d "$HOME_DIR" ]; then
        chown "$MAILUSER_FULL":acmecorp "$HOME_DIR" 2>/dev/null || true
        chmod 700 "$HOME_DIR" 2>/dev/null || true
    fi
done
echo "Maildir ownership fixed for domain mail users"

# ---------------------------------------------------------------
# 3. Detect PHP version and FPM pool file
# ---------------------------------------------------------------
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
if [ -z "$PHP_VERSION" ]; then
    echo "ERROR: Could not detect PHP version."
    exit 1
fi
echo "PHP version: $PHP_VERSION"

DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -z "$DOMAIN_ID" ]; then
    echo "ERROR: Could not get domain ID for acmecorp.test."
    exit 1
fi
echo "Domain ID: $DOMAIN_ID"

# Ensure PHP-FPM mode is enabled (domain may default to CGI)
CURRENT_MODE=$(virtualmin list-domains --domain acmecorp.test --multiline 2>/dev/null | grep "PHP execution mode" | awk '{print $NF}')
if [ "$CURRENT_MODE" != "fpm" ]; then
    echo "Switching PHP mode from $CURRENT_MODE to fpm..."
    virtualmin modify-web --domain acmecorp.test --mode fpm 2>/dev/null || true
    sleep 2
fi

POOL_FILE="/etc/php/${PHP_VERSION}/fpm/pool.d/${DOMAIN_ID}.conf"
if [ ! -f "$POOL_FILE" ]; then
    echo "WARNING: PHP-FPM pool file not found at $POOL_FILE"
    # Try alternate naming: some systems use the domain name
    POOL_FILE=$(find /etc/php/ -name "*.conf" -path "*/pool.d/*" 2>/dev/null | \
                xargs grep -l "acmecorp" 2>/dev/null | head -1)
    if [ -z "$POOL_FILE" ] || [ ! -f "$POOL_FILE" ]; then
        echo "ERROR: Cannot find PHP-FPM pool config for acmecorp.test"
        exit 1
    fi
fi
echo "Pool file: $POOL_FILE"

# Save the original socket path for reference
ORIGINAL_SOCKET=$(grep "^listen = " "$POOL_FILE" 2>/dev/null | awk -F' = ' '{print $2}' | tr -d ' ')
echo "$ORIGINAL_SOCKET" > /tmp/original_socket_path.txt
echo "Original PHP-FPM socket: $ORIGINAL_SOCKET"

# ---------------------------------------------------------------
# 4. Create the web application files (working state first)
# ---------------------------------------------------------------
echo "--- Creating application files ---"

mkdir -p /home/acmecorp/public_html/includes

# Create the PHP wrapper for index page so PHP-FPM breakage causes 503 on /
if [ -f /home/acmecorp/public_html/index.html ]; then
    mv /home/acmecorp/public_html/index.html /home/acmecorp/public_html/template.html
    echo "Renamed index.html -> template.html"
fi

cat > /home/acmecorp/public_html/index.php << 'PHPEOF'
<?php readfile(__DIR__ . '/template.html'); ?>
PHPEOF
chown acmecorp:acmecorp /home/acmecorp/public_html/index.php
chmod 644 /home/acmecorp/public_html/index.php

# Create the status page that checks DB connectivity
cat > /home/acmecorp/public_html/status.php << 'PHPEOF'
<?php
$config_path = __DIR__ . '/includes/db_config.php';
if (!is_readable($config_path)) {
    http_response_code(500);
    die("ERROR: Configuration file not readable - check file permissions");
}
$config = require $config_path;
try {
    $dsn = sprintf("mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4",
        $config['host'], $config['port'] ?? 3306, $config['name']);
    $pdo = new PDO($dsn, $config['user'], $config['pass'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_TIMEOUT => 5
    ]);
    $count = $pdo->query("SELECT COUNT(*) FROM actor")->fetchColumn();
    if ($count > 0) {
        echo "System Operational";
    } else {
        http_response_code(500);
        die("ERROR: Database integrity check failed - actor table empty");
    }
} catch (PDOException $e) {
    http_response_code(500);
    if (strpos($e->getMessage(), 'Connection refused') !== false) {
        die("ERROR: Database connection refused - check host and port");
    }
    if (strpos($e->getMessage(), 'Access denied') !== false) {
        die("ERROR: Database access denied - check credentials");
    }
    die("ERROR: Database error - " . $e->getMessage());
}
PHPEOF
chown acmecorp:acmecorp /home/acmecorp/public_html/status.php
chmod 644 /home/acmecorp/public_html/status.php

# Create the DB config with CORRECT credentials (will be broken later)
cat > /home/acmecorp/public_html/includes/db_config.php << 'PHPEOF'
<?php
return [
    'host' => '127.0.0.1',
    'port' => 3306,
    'user' => 'acmecorp',
    'pass' => 'GymAnything123!',
    'name' => 'sakila'
];
PHPEOF
chown acmecorp:acmecorp /home/acmecorp/public_html/includes/db_config.php
chmod 640 /home/acmecorp/public_html/includes/db_config.php

# ---------------------------------------------------------------
# 5. Verify everything works BEFORE introducing breakages
# ---------------------------------------------------------------
echo "--- Verifying pre-break state ---"
sleep 2

PRE_STATUS=$(curl -s -o /tmp/pre_check_body.txt -w "%{http_code}" \
    "http://localhost/status.php" --header "Host: acmecorp.test" 2>/dev/null || echo "000")
PRE_BODY=$(cat /tmp/pre_check_body.txt 2>/dev/null)
echo "Pre-break status.php: HTTP $PRE_STATUS — $PRE_BODY"
rm -f /tmp/pre_check_body.txt

if [ "$PRE_STATUS" != "200" ] || ! echo "$PRE_BODY" | grep -q "System Operational"; then
    echo "WARNING: Pre-break verification failed. Continuing anyway."
fi

# ---------------------------------------------------------------
# 6. BREAKAGE 1 — PHP-FPM listen mismatch
#    Change pool from Unix socket to TCP 127.0.0.1:9099.
#    Apache ProxyPassMatch still references the original Unix socket.
#    Effect: all PHP requests return 503 Service Unavailable.
# ---------------------------------------------------------------
echo "--- Applying breakage 1: PHP-FPM socket mismatch ---"
sed -i "s|^listen = .*|listen = 127.0.0.1:9099|" "$POOL_FILE"
systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null || true
echo "PHP-FPM pool now listens on 127.0.0.1:9099 (Apache expects $ORIGINAL_SOCKET)"

# ---------------------------------------------------------------
# 7. BREAKAGE 2 — Database credentials + permissions (two layers)
#    Layer A: db_config.php owned by root:root with mode 600
#             → web server cannot read it → "Configuration file not readable"
#    Layer B: MySQL password changed to MigratedPwd999!
#             → config still has old password → "Database access denied"
# ---------------------------------------------------------------
echo "--- Applying breakage 2: DB permissions + credentials ---"

# Layer A: wrong ownership and permissions
chown root:root /home/acmecorp/public_html/includes/db_config.php
chmod 600 /home/acmecorp/public_html/includes/db_config.php

# Layer B: change MySQL password (config file now has stale credentials)
mysql -u root -p'GymAnything123!' -e \
    "ALTER USER 'acmecorp'@'localhost' IDENTIFIED BY 'MigratedPwd999!';" 2>/dev/null || true
mysql -u root -p'GymAnything123!' -e "FLUSH PRIVILEGES;" 2>/dev/null || true
echo "MySQL password changed to MigratedPwd999!; config file has GymAnything123!"

# ---------------------------------------------------------------
# 8. BREAKAGE 3 — Postfix transport map routes domain to dead relay
#    Adds a transport_maps entry sending all acmecorp.test mail to
#    127.0.0.1:12345 (nothing listening there → immediate bounce).
# ---------------------------------------------------------------
echo "--- Applying breakage 3: Postfix transport mis-route ---"

# Flush any existing mail queue to avoid interference
postsuper -d ALL 2>/dev/null || true

postconf -e "transport_maps = hash:/etc/postfix/transport"
echo "acmecorp.test    smtp:[127.0.0.1]:12345" > /etc/postfix/transport
postmap /etc/postfix/transport
systemctl restart postfix 2>/dev/null || true
echo "Postfix transport routes acmecorp.test to dead relay at 127.0.0.1:12345"

# ---------------------------------------------------------------
# 9. Ensure DKIM / SPF / DMARC are NOT configured (clean slate)
# ---------------------------------------------------------------
echo "--- Clearing email authentication ---"
virtualmin set-dkim --disable 2>/dev/null || true
virtualmin modify-dns --domain acmecorp.test --no-spf 2>/dev/null || true
# Remove any pre-existing DMARC record from the zone
ZONE_FILE=$(find /var/lib/bind/ /etc/bind/zones/ /var/cache/bind/ \
    -name "acmecorp.test.hosts" -o -name "acmecorp.test.db" 2>/dev/null | head -1)
if [ -n "$ZONE_FILE" ] && [ -f "$ZONE_FILE" ]; then
    sed -i '/_dmarc/d' "$ZONE_FILE" 2>/dev/null || true
    rndc reload acmecorp.test 2>/dev/null || true
fi
echo "DKIM disabled, SPF removed, DMARC cleaned"

# ---------------------------------------------------------------
# 10. Record initial checksums for anti-gaming verification
# ---------------------------------------------------------------
echo "--- Recording initial checksums ---"
md5sum "$POOL_FILE" > /tmp/initial_checksums.txt 2>/dev/null
md5sum /home/acmecorp/public_html/includes/db_config.php >> /tmp/initial_checksums.txt 2>/dev/null
md5sum /etc/postfix/transport >> /tmp/initial_checksums.txt 2>/dev/null

# ---------------------------------------------------------------
# 11. Launch Firefox and navigate to the broken domain
# ---------------------------------------------------------------
echo "--- Preparing browser view ---"
ensure_virtualmin_ready

# Navigate to the broken website so the agent sees the 503 in Firefox
navigate_to "http://acmecorp.test/"
sleep 3

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Breakages applied:"
echo "  1. PHP-FPM listens on TCP 9099 (Apache expects Unix socket)"
echo "  2. db_config.php: root:root 600 + MySQL password changed"
echo "  3. Postfix routes acmecorp.test to dead relay 127.0.0.1:12345"
echo "  4. DKIM/SPF/DMARC not configured"
