#!/bin/bash
# Setup script for purge_botnet_and_cleanup task (pre_task hook)
# Injects botnet users, empty tags, and insecure registration settings.

echo "=== Setting up purge_botnet_and_cleanup task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# 1. Record Legitimate Baseline
# ============================================================
echo "Recording baseline of legitimate users and tags..."
LEGIT_AUTHOR_COUNT=$(wp_cli user list --role=author --format=count 2>/dev/null || echo "0")
LEGIT_SUBSCRIBER_COUNT=$(wp_cli user list --role=subscriber --format=count 2>/dev/null || echo "0")
LEGIT_ACTIVE_TAGS=$(wp_db_query "SELECT COUNT(*) FROM wp_term_taxonomy WHERE taxonomy='post_tag' AND count>0" 2>/dev/null || echo "0")

echo "Baseline Authors: $LEGIT_AUTHOR_COUNT"
echo "Baseline Subscribers: $LEGIT_SUBSCRIBER_COUNT"
echo "Baseline Active Tags: $LEGIT_ACTIVE_TAGS"

cat > /tmp/botnet_cleanup_baseline.json << EOF
{
    "legit_author_count": $LEGIT_AUTHOR_COUNT,
    "legit_subscriber_count": $LEGIT_SUBSCRIBER_COUNT,
    "legit_active_tags": $LEGIT_ACTIVE_TAGS
}
EOF
chmod 666 /tmp/botnet_cleanup_baseline.json

# ============================================================
# 2. Inject Insecure Settings
# ============================================================
echo "Injecting insecure registration settings..."
wp_cli option update users_can_register 1
wp_cli option update default_role "contributor"

# ============================================================
# 3. Inject Specific Spammer & Content
# ============================================================
echo "Creating spam_master user and malicious content..."
# Delete if exists from previous run
wp_cli user delete spam_master --yes 2>/dev/null || true
wp_cli user create spam_master spam_master@botnet.xyz --role=author --user_pass="SpamPass123!" --display_name="Spam Master"

SPAM_MASTER_ID=$(wp_cli user get spam_master --field=ID 2>/dev/null)
if [ -n "$SPAM_MASTER_ID" ]; then
    wp_cli post create --post_title="Spam Post Alpha: Buy Cheap Crypto" --post_content="Click here for cheap crypto!" --post_author=$SPAM_MASTER_ID --post_status=publish
    wp_cli post create --post_title="Spam Post Beta: Free Gift Cards" --post_content="Claim your free gift card now!" --post_author=$SPAM_MASTER_ID --post_status=publish
    wp_cli post create --post_title="Spam Post Gamma: SEO Backlinks" --post_content="Get #1 on Google guaranteed!" --post_author=$SPAM_MASTER_ID --post_status=publish
fi

# ============================================================
# 4. Inject Botnet Accounts
# ============================================================
echo "Injecting 12 botnet accounts (Contributor role)..."
for i in {1..12}; do
    wp_cli user create "bot_user_$i" "bot$i@spamnetwork.com" --role=contributor --user_pass="BotPass123!" 2>/dev/null || true
done

# ============================================================
# 5. Inject Orphaned Tags
# ============================================================
echo "Injecting 15 orphaned (empty) tags..."
SPAM_TAGS=(
    "buy-crypto" "free-movies" "cheap-meds" "casino-bonus" "viagra-online" 
    "seo-services" "backlinks" "gift-card" "lottery-winner" "crypto-wallet"
    "fast-cash" "payday-loan" "weight-loss-pill" "followers-buy" "hot-singles"
)

for tag in "${SPAM_TAGS[@]}"; do
    wp_cli term create post_tag "$tag" 2>/dev/null || true
done

# ============================================================
# 6. Ensure Firefox is running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="