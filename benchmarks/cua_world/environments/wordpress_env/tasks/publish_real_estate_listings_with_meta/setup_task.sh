#!/bin/bash
echo "=== Setting up publish_real_estate_listings_with_meta task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# Clean slate: Ensure "Properties" category doesn't exist yet
cd /var/www/html/wordpress
if wp term get category Properties --field=term_id --allow-root 2>/dev/null; then
    echo "Removing existing Properties category for a clean start..."
    wp term delete category Properties --by=name --allow-root 2>/dev/null || true
fi

# Clean slate: Ensure expected posts do not exist
EXPECTED_TITLES=(
    "8424 Bluebonnet Lane, Austin, TX 78758"
    "1904 Ocean Drive, Miami Beach, FL 33139"
    "755 Pinecone Ridge, Denver, CO 80204"
)

for TITLE in "${EXPECTED_TITLES[@]}"; do
    POST_ID=$(wp post list --post_type=post --title="$TITLE" --field=ID --allow-root 2>/dev/null)
    if [ -n "$POST_ID" ]; then
        echo "Removing pre-existing post: $TITLE"
        wp post delete "$POST_ID" --force --allow-root 2>/dev/null || true
    fi
done

# Ensure Firefox is running and focused on WordPress admin
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
else
    echo "WARNING: No Firefox window found!"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="