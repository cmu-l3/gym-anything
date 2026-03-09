#!/bin/bash
# Setup script for edit_page task (pre_task hook)
# Records initial state of the About Us page

echo "=== Setting up edit_page task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Find the About Us page
ABOUT_PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='About Us' AND post_type='page' AND post_status='publish' LIMIT 1")

if [ -n "$ABOUT_PAGE_ID" ]; then
    echo "Found About Us page with ID: $ABOUT_PAGE_ID"
    echo "$ABOUT_PAGE_ID" | sudo tee /tmp/about_page_id > /dev/null
    sudo chmod 666 /tmp/about_page_id

    # Save initial title and content
    INITIAL_TITLE=$(wp_db_query "SELECT post_title FROM wp_posts WHERE ID=$ABOUT_PAGE_ID")
    INITIAL_CONTENT=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$ABOUT_PAGE_ID")
    INITIAL_MODIFIED=$(wp_db_query "SELECT post_modified FROM wp_posts WHERE ID=$ABOUT_PAGE_ID")

    echo "$INITIAL_TITLE" | sudo tee /tmp/initial_page_title > /dev/null
    echo "$INITIAL_CONTENT" | sudo tee /tmp/initial_page_content > /dev/null
    echo "$INITIAL_MODIFIED" | sudo tee /tmp/initial_page_modified > /dev/null
    sudo chmod 666 /tmp/initial_page_title /tmp/initial_page_content /tmp/initial_page_modified

    echo "Initial title: $INITIAL_TITLE"
    echo "Initial content length: ${#INITIAL_CONTENT}"
    echo "Last modified: $INITIAL_MODIFIED"
else
    echo "WARNING: About Us page not found!"
    echo "Creating About Us page for task..."

    # Create the About Us page if it doesn't exist
    cd /var/www/html/wordpress
    wp post create --post_type=page --post_status=publish --post_title="About Us" \
        --post_content="<h2>Welcome to Our Blog</h2><p>We are passionate about WordPress and helping others succeed online.</p>" \
        --allow-root 2>&1

    # Get the new page ID
    ABOUT_PAGE_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE post_title='About Us' AND post_type='page' ORDER BY ID DESC LIMIT 1")
    echo "$ABOUT_PAGE_ID" | sudo tee /tmp/about_page_id > /dev/null
    sudo chmod 666 /tmp/about_page_id
    echo "Created About Us page with ID: $ABOUT_PAGE_ID"
fi

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."

# Check if Firefox is running
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "WARNING: Firefox is not running! Attempting to restart..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
else
    echo "WARNING: No Firefox window found!"
    DISPLAY=:1 wmctrl -l
fi

# Verify Firefox is visible
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
echo "Current windows: $WINDOW_LIST"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent should now:"
echo "  1. Navigate to Pages in WordPress admin"
echo "  2. Edit the 'About Us' page"
echo "  3. Change title to 'About Our Team'"
echo "  4. Add 'Our Values' section with Innovation, Integrity, Excellence"
echo "  5. Update the page"
