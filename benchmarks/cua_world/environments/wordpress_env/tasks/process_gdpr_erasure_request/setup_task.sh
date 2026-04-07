#!/bin/bash
# Setup script for process_gdpr_erasure_request task

echo "=== Setting up process_gdpr_erasure_request task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# 1. Create the legal_holds directory
mkdir -p /home/ga/legal_holds/
chown ga:ga /home/ga/legal_holds/
chmod 755 /home/ga/legal_holds/

# 2. Setup the target user and their content via WP-CLI
cd /var/www/html/wordpress

# Clean up if exists from previous run
wp user delete alex_rebel --yes --allow-root 2>/dev/null || true

echo "Creating target user..."
wp user create alex_rebel alex.rebel@example.com \
    --role=author \
    --first_name="Alex" \
    --last_name="Rebel" \
    --user_pass="T3mpP@ssw0rd!" \
    --allow-root

ALEX_ID=$(wp user get alex_rebel --field=ID --allow-root)

if [ -z "$ALEX_ID" ]; then
    echo "ERROR: Failed to create target user."
    exit 1
fi

echo "Creating posts authored by target user..."
P1=$(wp post create --post_title="Top 5 Tech Trends for 2026" --post_content="Content discussing technology trends." --post_status=publish --post_author=$ALEX_ID --porcelain --allow-root)
P2=$(wp post create --post_title="Why AI Matters in Modern Business" --post_content="Content discussing AI." --post_status=publish --post_author=$ALEX_ID --porcelain --allow-root)
P3=$(wp post create --post_title="The Future of Web Development" --post_content="Content discussing web dev." --post_status=publish --post_author=$ALEX_ID --porcelain --allow-root)

echo "$P1" > /tmp/alex_post_1
echo "$P2" > /tmp/alex_post_2
echo "$P3" > /tmp/alex_post_3
chmod 666 /tmp/alex_post_*

echo "Creating dummy post by admin to receive comments..."
ADMIN_ID=$(wp user get admin --field=ID --allow-root)
DP=$(wp post create --post_title="Welcome to our new community" --post_content="Feel free to leave comments!" --post_status=publish --post_author=$ADMIN_ID --porcelain --allow-root)

echo "Creating comments by target user..."
C1=$(wp comment create --comment_post_ID=$DP --comment_author="Alex Rebel" --comment_author_email="alex.rebel@example.com" --comment_content="Great initiative, happy to be here." --user_id=$ALEX_ID --porcelain --allow-root)
C2=$(wp comment create --comment_post_ID=$DP --comment_author="Alex Rebel" --comment_author_email="alex.rebel@example.com" --comment_content="I have a question about the guidelines." --user_id=$ALEX_ID --porcelain --allow-root)
C3=$(wp comment create --comment_post_ID=$DP --comment_author="Alex Rebel" --comment_author_email="alex.rebel@example.com" --comment_content="Thanks for clarifying." --user_id=$ALEX_ID --porcelain --allow-root)

echo "$C1" > /tmp/alex_comment_1
echo "$C2" > /tmp/alex_comment_2
echo "$C3" > /tmp/alex_comment_3
chmod 666 /tmp/alex_comment_*

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time
chmod 666 /tmp/task_start_time

# 3. Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Focus and maximize Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target User: alex_rebel (alex.rebel@example.com)"