#!/bin/bash
set -e
echo "=== Exporting Payment Gateway Configuration Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

WP_DIR="/var/www/html/wordpress"
cd "$WP_DIR"

# ============================================================
# Query Database for Payment Settings
# ============================================================
echo "Querying payment settings..."

# 1. Get BACS Settings (Main options)
BACS_SETTINGS_JSON=$(wp option get woocommerce_bacs_settings --format=json --allow-root 2>/dev/null || echo "{}")

# 2. Get BACS Accounts (Bank Details)
# These are stored in a separate option 'woocommerce_bacs_accounts'
# Note: WP-CLI output for serialized arrays can be tricky; using json output helps
BACS_ACCOUNTS_JSON=$(wp option get woocommerce_bacs_accounts --format=json --allow-root 2>/dev/null || echo "[]")

# 3. Get Cheque Settings
CHEQUE_SETTINGS_JSON=$(wp option get woocommerce_cheque_settings --format=json --allow-root 2>/dev/null || echo "{}")

# 4. Get COD Settings
COD_SETTINGS_JSON=$(wp option get woocommerce_cod_settings --format=json --allow-root 2>/dev/null || echo "{}")

# Check if application (Firefox) was running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# We construct the JSON carefully to embed the inner JSON strings or objects
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "bacs_settings": $BACS_SETTINGS_JSON,
    "bacs_accounts": $BACS_ACCOUNTS_JSON,
    "cheque_settings": $CHEQUE_SETTINGS_JSON,
    "cod_settings": $COD_SETTINGS_JSON,
    "initial_state_file": "/tmp/initial_state.json"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="