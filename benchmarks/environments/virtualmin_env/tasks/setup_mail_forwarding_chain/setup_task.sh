#!/bin/bash
echo "=== Setting up setup_mail_forwarding_chain task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type virtualmin_list_domains &>/dev/null; then
    echo "WARNING: task_utils.sh functions not available, using inline definitions"
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
    ensure_virtualmin_ready() { true; }
    navigate_to() {
        DISPLAY=:1 xdotool key ctrl+l; sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "$1"; sleep 0.3
        DISPLAY=:1 xdotool key Return; sleep 4
    }
fi

TARGET_DOMAIN="acmecorp.test"

# Verify domain exists
if ! virtualmin list-domains --name-only 2>/dev/null | grep -q "^${TARGET_DOMAIN}$"; then
    echo "ERROR: ${TARGET_DOMAIN} does not exist!"
    exit 1
fi

# Clean up any previous run artifacts
echo "--- Cleaning up previous run artifacts ---"
for user in hr billing; do
    virtualmin delete-user --domain "$TARGET_DOMAIN" --user "$user" 2>/dev/null || true
done
for alias in jobs invoices contact; do
    virtualmin delete-alias --domain "$TARGET_DOMAIN" --from "$alias" 2>/dev/null || true
done
sleep 2

# Record baseline state
echo "--- Recording baseline state ---"
INITIAL_USERS=$(virtualmin list-users --domain "$TARGET_DOMAIN" --name-only 2>/dev/null)
INITIAL_USER_COUNT=$(echo "$INITIAL_USERS" | grep -c . 2>/dev/null || echo "0")
INITIAL_ALIASES=$(virtualmin list-aliases --domain "$TARGET_DOMAIN" 2>/dev/null)
INITIAL_ALIAS_COUNT=$(echo "$INITIAL_ALIASES" | grep -c "@" 2>/dev/null || echo "0")

echo "$INITIAL_USERS" > /tmp/initial_users
echo "$INITIAL_ALIASES" > /tmp/initial_aliases
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count
echo "$INITIAL_ALIAS_COUNT" > /tmp/initial_alias_count

cat > /tmp/initial_mail_state.json << EOF
{
    "domain": "${TARGET_DOMAIN}",
    "initial_user_count": ${INITIAL_USER_COUNT:-0},
    "initial_alias_count": ${INITIAL_ALIAS_COUNT:-0}
}
EOF

cat /tmp/initial_mail_state.json

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is ready
ensure_virtualmin_ready
sleep 2

# Navigate to Virtualmin dashboard — agent must find the right pages
navigate_to "https://localhost:10000/virtual-server/index.cgi"
sleep 3

take_screenshot /tmp/task_start_screenshot.png
echo "=== setup_mail_forwarding_chain task setup complete ==="
