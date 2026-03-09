#!/bin/bash
set -e
echo "=== Setting up Configure Payment Gateways Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# CRITICAL: Ensure WordPress/WooCommerce is installed
WP_DIR="/var/www/html/wordpress"
if [ ! -d "$WP_DIR" ]; then
    echo "ERROR: WordPress directory not found at $WP_DIR"
    exit 1
fi
cd "$WP_DIR"

# ============================================================
# Set Initial State
# ============================================================
echo "Configuring initial payment gateway states..."

# 1. Reset BACS (Bank Transfer) to DISABLED and clear settings
wp option update woocommerce_bacs_settings --format=json '{"enabled":"no","title":"Direct bank transfer","description":"Make your payment directly into our bank account.","instructions":"","account_details":""}' --allow-root 2>&1 || true
wp option delete woocommerce_bacs_accounts --allow-root 2>&1 || true

# 2. Reset Cheque (Check Payments) to DISABLED and clear settings
wp option update woocommerce_cheque_settings --format=json '{"enabled":"no","title":"Check payments","description":"Please send a check to Store Name.","instructions":""}' --allow-root 2>&1 || true

# 3. Set COD (Cash on Delivery) to ENABLED (Agent must disable this)
wp option update woocommerce_cod_settings --format=json '{"enabled":"yes","title":"Cash on delivery","description":"Pay with cash upon delivery.","instructions":"","enable_for_methods":[],"enable_for_virtual":"yes"}' --allow-root 2>&1 || true

# Record initial state for anti-gaming verification
echo "Recording initial state..."
cat > /tmp/initial_state.json << EOF
{
  "bacs_enabled": "no",
  "cheque_enabled": "no",
  "cod_enabled": "yes"
}
EOF

# ============================================================
# Launch Browser
# ============================================================
echo "Launching Firefox..."

# Kill any existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 1

# Start Firefox pointing to the Payments settings tab to save time/clicks
# or just the dashboard if we want them to navigate
START_URL="http://localhost/wp-admin/admin.php?page=wc-settings&tab=checkout"

su - ga -c "DISPLAY=:1 firefox --no-remote '$START_URL' &" 2>/dev/null
sleep 5

# Wait for window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="