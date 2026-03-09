#!/bin/bash
echo "=== Setting up configure_domain_resource_limits task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type virtualmin_list_domains &>/dev/null; then
    echo "WARNING: task_utils.sh functions not available, using inline definitions"
    virtualmin_list_domains() { virtualmin list-domains --name-only 2>/dev/null || true; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
    navigate_to() {
        local url="$1"
        DISPLAY=:1 xdotool key ctrl+l; sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "$url"; sleep 0.3
        DISPLAY=:1 xdotool key Return; sleep 4
    }
    ensure_virtualmin_ready() { true; }
fi

TARGET_DOMAIN="greenvalley.test"

# Verify domain exists
if ! virtualmin list-domains --name-only 2>/dev/null | grep -q "^${TARGET_DOMAIN}$"; then
    echo "ERROR: ${TARGET_DOMAIN} does not exist!"
    exit 1
fi

# Record baseline state: current limits for greenvalley.test
echo "--- Recording baseline state ---"
DOMAIN_INFO=$(virtualmin list-domains --domain "$TARGET_DOMAIN" --multiline 2>/dev/null)
echo "$DOMAIN_INFO" > /tmp/initial_domain_info

# Extract current values
INITIAL_QUOTA=$(echo "$DOMAIN_INFO" | grep -i "server byte quota" | awk '{print $NF}')
INITIAL_BW=$(echo "$DOMAIN_INFO" | grep -i "bandwidth limit" | awk '{print $NF}')
INITIAL_MAX_MAILBOXES=$(echo "$DOMAIN_INFO" | grep -i "maximum mailboxes" | awk '{print $NF}' | head -1)
INITIAL_MAX_ALIASES=$(echo "$DOMAIN_INFO" | grep -i "maximum aliases" | awk '{print $NF}' | head -1)
INITIAL_MAX_DBS=$(echo "$DOMAIN_INFO" | grep -i "maximum databases" | awk '{print $NF}' | head -1)

cat > /tmp/initial_limits.json << EOF
{
    "domain": "${TARGET_DOMAIN}",
    "initial_quota": "${INITIAL_QUOTA:-NONE}",
    "initial_bw": "${INITIAL_BW:-NONE}",
    "initial_max_mailboxes": "${INITIAL_MAX_MAILBOXES:-NONE}",
    "initial_max_aliases": "${INITIAL_MAX_ALIASES:-NONE}",
    "initial_max_dbs": "${INITIAL_MAX_DBS:-NONE}"
}
EOF

cat /tmp/initial_limits.json

# Reset limits to unlimited (ensure the agent has to set them)
echo "--- Resetting limits to unlimited ---"
virtualmin modify-domain --domain "$TARGET_DOMAIN" \
    --quota UNLIMITED --uquota UNLIMITED \
    --bw NONE 2>&1 | tail -3 || true
virtualmin modify-limits --domain "$TARGET_DOMAIN" \
    --max-mailboxes UNLIMITED --max-aliases UNLIMITED \
    --max-dbs UNLIMITED 2>&1 | tail -3 || true

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is ready and logged into Virtualmin
ensure_virtualmin_ready
sleep 2

# Navigate to the Virtualmin dashboard (not directly to the edit page)
navigate_to "https://localhost:10000/virtual-server/index.cgi"
sleep 3

take_screenshot /tmp/task_start_screenshot.png
echo "=== configure_domain_resource_limits task setup complete ==="
