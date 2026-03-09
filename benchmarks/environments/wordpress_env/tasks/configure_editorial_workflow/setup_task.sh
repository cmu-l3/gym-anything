#!/bin/bash
# Setup script for configure_editorial_workflow task (pre_task hook)
# Ensures required users and categories exist. Records baseline.

echo "=== Setting up configure_editorial_workflow task ==="

source /workspace/scripts/task_utils.sh

cd /var/www/html/wordpress

# ============================================================
# Ensure required users exist
# ============================================================
echo "Verifying required users..."

# editor user
if ! user_exists "editor"; then
    echo "Creating 'editor' user..."
    wp user create editor editor@example.com --role=editor \
        --first_name="Emma" --last_name="Editor" --user_pass="Editor123!" --allow-root 2>&1
else
    echo "User 'editor' already exists"
fi

# author user
if ! user_exists "author"; then
    echo "Creating 'author' user..."
    wp user create author author@example.com --role=author \
        --first_name="Alex" --last_name="Author" --user_pass="Author123!" --allow-root 2>&1
else
    echo "User 'author' already exists"
fi

# contributor user
if ! user_exists "contributor"; then
    echo "Creating 'contributor' user..."
    wp user create contributor contributor@example.com --role=contributor \
        --first_name="Chris" --last_name="Contributor" --user_pass="Contributor123!" --allow-root 2>&1
else
    echo "User 'contributor' already exists"
fi

# List users
echo ""
echo "Current users:"
wp_cli user list --fields=ID,user_login,user_email,roles

# ============================================================
# Ensure required categories exist
# ============================================================
echo ""
echo "Verifying categories..."
for cat in "News" "Technology" "Lifestyle"; do
    if category_exists "$cat"; then
        echo "Category '$cat' exists"
    else
        echo "Creating category '$cat'..."
        wp term create category "$cat" --allow-root 2>&1 || true
    fi
done

# ============================================================
# Record baseline
# ============================================================
INITIAL_POST_COUNT=$(wp_cli post list --post_type=post --post_status=any --format=count)
echo ""
echo "Initial total post count (all statuses): $INITIAL_POST_COUNT"
echo "$INITIAL_POST_COUNT" | sudo tee /tmp/initial_editorial_post_count > /dev/null
sudo chmod 666 /tmp/initial_editorial_post_count

# Clean up any posts from previous runs with matching titles
for title in "Q1 2026 Revenue Analysis" "Spring Product Launch Preview" "Annual Team Building Event Recap"; do
    OLD_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='$title' AND post_type='post' ORDER BY ID DESC LIMIT 1")
    if [ -n "$OLD_ID" ]; then
        echo "Removing old post '$title' (ID: $OLD_ID) from previous run..."
        wp post delete "$OLD_ID" --force --allow-root 2>/dev/null || true
    fi
done

# Update baseline after cleanup
INITIAL_POST_COUNT=$(wp_cli post list --post_type=post --post_status=any --format=count)
echo "$INITIAL_POST_COUNT" | sudo tee /tmp/initial_editorial_post_count > /dev/null

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# Ensure Firefox is running
# ============================================================
echo ""
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/?autologin=admin' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent must create 3 posts with specific authors, categories, and scheduling."
