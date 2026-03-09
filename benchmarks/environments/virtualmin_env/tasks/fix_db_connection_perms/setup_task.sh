#!/bin/bash
set -e
echo "=== Setting up fix_db_connection_perms task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure acmecorp.test domain exists
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "Creating acmecorp.test domain..."
    virtualmin create-domain \
        --domain acmecorp.test \
        --pass GymAnything123! \
        --unix --dir --webmin --web --dns --mail --mysql \
        --default-features
else
    echo "acmecorp.test domain already exists."
    # Reset password to ensure our "fix" will work
    virtualmin modify-user --domain acmecorp.test --user acmecorp --pass GymAnything123!
    virtualmin modify-database-user --domain acmecorp.test --user acmecorp --pass GymAnything123! --type mysql
fi

# 2. Setup file paths
WEB_ROOT="/home/acmecorp/public_html"
INC_DIR="$WEB_ROOT/includes"

mkdir -p "$INC_DIR"

# 3. Create the BROKEN config file
# - Wrong password: WrongPass123
# - We will set permissions later
cat > "$INC_DIR/db_config.php" << 'EOF'
<?php
// Database Configuration
$db_host = 'localhost';
$db_name = 'acmecorp';
$db_user = 'acmecorp';
$db_pass = 'WrongPass123'; // FIXME: Incorrect password

function get_db_connection() {
    global $db_host, $db_user, $db_pass, $db_name;
    // Suppress error display to simulate generic 500 or connection error
    $conn = new mysqli($db_host, $db_user, $db_pass, $db_name);
    if ($conn->connect_error) {
        die("Database Connection Failed");
    }
    return $conn;
}
?>
EOF

# 4. Create the status page
cat > "$WEB_ROOT/status.php" << 'EOF'
<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once('includes/db_config.php');

$conn = get_db_connection();
if ($conn) {
    echo "System Operational";
    $conn->close();
}
?>
EOF

# 5. Set Ownership and Permissions
# Correct ownership
chown -R acmecorp:acmecorp "$WEB_ROOT"

# Set status.php to correct permissions
chmod 644 "$WEB_ROOT/status.php"

# Set db_config.php to BAD permissions (777)
# In Virtualmin/suexec environments, 777 usually triggers a 500 Internal Server Error
chmod 777 "$INC_DIR/db_config.php"

echo "Files created and permissions broken."

# 6. Ensure Virtualmin is ready in Firefox
ensure_virtualmin_ready

# 7. Navigate to the Domain Summary page (starting point)
# The agent must find the File Manager from here
ACME_ID=$(get_domain_id "acmecorp.test")
navigate_to "https://localhost:10000/virtual-server/domain_menu.cgi?dom=${ACME_ID}"
sleep 5

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="