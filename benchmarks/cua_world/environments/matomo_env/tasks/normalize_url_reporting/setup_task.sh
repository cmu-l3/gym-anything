#!/bin/bash
# Setup script for Normalize URL Reporting task

echo "=== Setting up Normalize URL Reporting Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ── Clean up & Seed Target Site ───────────────────────────────────────────
TARGET_SITE="TechGadgets Shop"
CONTROL_SITE="Initial Site"

# Remove target site if it exists to ensure clean state
echo "Resetting target site: $TARGET_SITE..."
matomo_query "DELETE FROM matomo_site WHERE name='$TARGET_SITE'" 2>/dev/null || true

# Ensure Initial Site exists (Control)
CONTROL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE name='$CONTROL_SITE'" 2>/dev/null || echo "0")
if [ "$CONTROL_COUNT" = "0" ] || [ -z "$CONTROL_COUNT" ]; then
    echo "Creating control site..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login) VALUES ('$CONTROL_SITE', 'https://example.com', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 1, 'admin')" 2>/dev/null
fi

# Create Target Site with "bad" defaults (fragments=1, no exclusions)
echo "Creating target site..."
# keep_url_fragment=1 (default is usually 1 or 0 depending on version, forcing 1 to ensure task is meaningful)
# excluded_parameters='' (empty)
matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login) VALUES ('$TARGET_SITE', 'https://shop.techgadgets.test', NOW(), 1, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 1, 'admin')" 2>/dev/null

# ── Record Initial State for Verification ─────────────────────────────────
echo "Recording baseline configuration..."

# Get ID and state of Control Site
CONTROL_DATA=$(matomo_query "SELECT idsite, excluded_parameters, keep_url_fragment FROM matomo_site WHERE name='$CONTROL_SITE' LIMIT 1" 2>/dev/null)
# Get ID and state of Target Site
TARGET_DATA=$(matomo_query "SELECT idsite, excluded_parameters, keep_url_fragment FROM matomo_site WHERE name='$TARGET_SITE' LIMIT 1" 2>/dev/null)

# Save to JSON for verifier to check "do no harm" rule
cat > /tmp/initial_state.json << EOF
{
    "control_site": {
        "idsite": "$(echo "$CONTROL_DATA" | cut -f1)",
        "excluded_parameters": "$(echo "$CONTROL_DATA" | cut -f2)",
        "keep_url_fragment": "$(echo "$CONTROL_DATA" | cut -f3)"
    },
    "target_site": {
        "idsite": "$(echo "$TARGET_DATA" | cut -f1)",
        "excluded_parameters": "$(echo "$TARGET_DATA" | cut -f2)",
        "keep_url_fragment": "$(echo "$TARGET_DATA" | cut -f3)"
    },
    "timestamp": "$(date +%s)"
}
EOF

echo "Baseline recorded:"
cat /tmp/initial_state.json

# ── Application Setup ─────────────────────────────────────────────────────
# Ensure Firefox is running and logged in
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Navigate to dashboard
su - ga -c "DISPLAY=:1 firefox 'http://localhost/' > /tmp/firefox_task.log 2>&1 &"
sleep 5

if ! wait_for_window "firefox\|mozilla\|Matomo" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="