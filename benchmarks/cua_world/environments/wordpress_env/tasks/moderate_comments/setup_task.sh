#!/bin/bash
# Setup script for moderate_comments task
# Clears existing comments and injects a mix of legitimate and spam comments

echo "=== Setting up moderate_comments task ==="

source /workspace/scripts/task_utils.sh

cd /var/www/html/wordpress

# Enable comment moderation setting
wp option update comment_moderation 1 --allow-root 2>/dev/null

# Clear all existing comments to provide a clean state
echo "Clearing existing comments..."
EXISTING_COMMENTS=$(wp comment list --format=ids --allow-root 2>/dev/null)
if [ -n "$EXISTING_COMMENTS" ]; then
    wp comment delete $EXISTING_COMMENTS --force --allow-root 2>/dev/null || true
fi

# Find a published post to attach comments to, or create one if none exist
POST_ID=$(wp post list --post_type=post --post_status=publish --format=ids --allow-root 2>/dev/null | awk '{print $1}')
if [ -z "$POST_ID" ]; then
    echo "No published posts found. Creating a placeholder post..."
    POST_ID=$(wp post create --post_type=post --post_status=publish --post_title="Welcome to our Blog" --post_content="This is a test post for comments." --porcelain --allow-root)
fi
echo "Using Post ID: $POST_ID for comments"

# ============================================================
# Create 3 Legitimate Comments
# ============================================================
echo "Injecting legitimate comments..."

wp comment create --comment_post_ID="$POST_ID" \
    --comment_author="David Chen" \
    --comment_author_email="david@example.com" \
    --comment_content="Great article! Do you have any recommendations for backup plugins? I want to make sure my site is safe before making major changes." \
    --comment_approved=0 --allow-root 2>/dev/null

SARAH_ID=$(wp comment create --comment_post_ID="$POST_ID" \
    --comment_author="Sarah Mitchell" \
    --comment_author_email="sarah.m@smallbiz.net" \
    --comment_content="I'm debating between Yoast SEO and Rank Math for my small business site. Any thoughts on which is better for a beginner?" \
    --comment_approved=0 --porcelain --allow-root 2>/dev/null)
# Save Sarah's comment ID so the verifier knows what parent ID to look for
echo "$SARAH_ID" > /tmp/sarah_comment_id

wp comment create --comment_post_ID="$POST_ID" \
    --comment_author="Maria Rodriguez" \
    --comment_author_email="mrodriguez@contentwriters.org" \
    --comment_content="The section on content writing really resonated with me. Consistency is definitely key to building an audience." \
    --comment_approved=0 --allow-root 2>/dev/null

# ============================================================
# Create 4 Spam Comments
# ============================================================
echo "Injecting spam comments..."

wp comment create --comment_post_ID="$POST_ID" \
    --comment_author="BestPricesMeds" \
    --comment_author_email="sales@cheap-pharmacy-spam.xyz" \
    --comment_author_url="http://cheap-pharmacy-spam.xyz" \
    --comment_content="Buy ch3ap m3ds online without pr3scription! Visit our ph@rmacy today for the best deals! http://cheap-pharmacy-spam.xyz" \
    --comment_approved=0 --allow-root 2>/dev/null

wp comment create --comment_post_ID="$POST_ID" \
    --comment_author="SEOExpert2024" \
    --comment_author_email="seo@guaranteed-page-one.net" \
    --comment_author_url="http://fake-seo-services.net" \
    --comment_content="Get your website on page 1 of Google guaranteed! Buy our SEO package now and dominate your competitors! http://fake-seo-services.net" \
    --comment_approved=0 --allow-root 2>/dev/null

wp comment create --comment_post_ID="$POST_ID" \
    --comment_author="CryptoKing99" \
    --comment_author_email="king@crypto-scam-site.biz" \
    --comment_author_url="http://crypto-scam-site.biz" \
    --comment_content="I made \$10,000 in one week trading crypto with this one weird trick! Click here to learn my secret strategy: http://crypto-scam-site.biz" \
    --comment_approved=0 --allow-root 2>/dev/null

wp comment create --comment_post_ID="$POST_ID" \
    --comment_author="FreeGiftCards" \
    --comment_author_email="winner@phishing-gift-card.com" \
    --comment_author_url="http://phishing-gift-card.com" \
    --comment_content="Congratulations! You've been selected to win a free \$500 Amazon gift card! Claim your prize here immediately: http://phishing-gift-card.com" \
    --comment_approved=0 --allow-root 2>/dev/null

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp
chmod 666 /tmp/sarah_comment_id 2>/dev/null || true

# ============================================================
# Ensure Firefox is running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus and maximize Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "7 comments (3 legit, 4 spam) are now pending moderation."