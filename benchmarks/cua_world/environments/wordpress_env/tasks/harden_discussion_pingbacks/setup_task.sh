#!/bin/bash
# Setup script for harden_discussion_pingbacks task
# Injects vulnerable discussion settings, opens pingbacks on existing posts,
# and generates a mix of spam pingbacks and a legitimate comment.

echo "=== Setting up harden_discussion_pingbacks task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

cd /var/www/html/wordpress

# ============================================================
# 1. Set global discussion defaults to vulnerable state
# ============================================================
echo "Setting lenient global discussion settings..."
wp_cli option update default_ping_status "open"
wp_cli option update close_comments_for_old_posts "0"
wp_cli option update close_comments_days_old "14"
wp_cli option update comment_max_links "2"

# ============================================================
# 2. Retroactively open pingbacks on all published posts
# ============================================================
echo "Opening pingbacks on all existing posts..."
wp_db_query "UPDATE wp_posts SET ping_status='open' WHERE post_type='post' AND post_status='publish'"

# ============================================================
# 3. Create Spam Pingbacks & Legitimate Comment
# ============================================================
echo "Injecting comment queue..."

# Clear existing pending comments to have a clean slate for the test
wp_db_query "DELETE FROM wp_comments WHERE comment_approved='0'"

# Get a few valid post IDs to attach comments to
POST_IDS=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='post' AND post_status='publish' LIMIT 3")
read -r POST_ID_1 POST_ID_2 POST_ID_3 <<< $(echo $POST_IDS | tr '\n' ' ')

# If we don't have enough posts, just use the first one available
if [ -z "$POST_ID_1" ]; then
    wp_cli post create --post_type=post --post_title="Sample Post" --post_status=publish
    POST_ID_1=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_type='post' AND post_status='publish' LIMIT 1")
    POST_ID_2=$POST_ID_1
    POST_ID_3=$POST_ID_1
fi
[ -z "$POST_ID_2" ] && POST_ID_2=$POST_ID_1
[ -z "$POST_ID_3" ] && POST_ID_3=$POST_ID_1

# Create spam pingbacks
wp_cli comment create --comment_post_ID=$POST_ID_1 --comment_author="Cheap Casino" --comment_author_url="http://spamsite1.xyz" --comment_type="pingback" --comment_approved="0" --comment_content="[...] check out this great site [...]"
wp_cli comment create --comment_post_ID=$POST_ID_2 --comment_author="Buy Watches" --comment_author_url="http://spamsite2.xyz" --comment_type="pingback" --comment_approved="0" --comment_content="[...] discount watches available here [...]"
wp_cli comment create --comment_post_ID=$POST_ID_3 --comment_author="Crypto King" --comment_author_url="http://spamsite3.xyz" --comment_type="pingback" --comment_approved="0" --comment_content="[...] invest in crypto today [...]"

# Create a legitimate pending comment (MUST NOT BE DELETED BY AGENT)
wp_cli comment create --comment_post_ID=$POST_ID_1 --comment_author="Jane Doe" --comment_author_email="jane.doe@example.com" --comment_type="comment" --comment_approved="0" --comment_content="Great article! I have a question about how this applies to modern web environments. Can you provide more details?"

echo "Comments injected successfully."

# ============================================================
# Ensure Firefox is running and focused on WP Admin
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/?autologin=admin' > /tmp/firefox_restart.log 2>&1 &"
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