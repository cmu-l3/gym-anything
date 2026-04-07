#!/bin/bash
set -e
echo "=== Setting up PR Crisis task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for verification
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# 1. Create the flawed original data
# ============================================================
echo "Creating flawed original data..."
mkdir -p /tmp/pr_data
cat > /tmp/pr_data/Q3-2024-Financial-Data.csv << 'EOF'
Quarter,Revenue,Profit
Q3 2024,$1000000,$50000
CONFIDENTIAL - DO NOT DISTRIBUTE
EOF

# ============================================================
# 2. Create the corrected data for the agent
# ============================================================
echo "Creating corrected data for the agent..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/CORRECTED_Q3_Data.csv << 'EOF'
Quarter,Revenue,Profit
Q3 2024,$1000000,$500000
CONFIDENTIAL - DO NOT DISTRIBUTE
EOF
chown ga:ga /home/ga/Documents/CORRECTED_Q3_Data.csv
chmod 644 /home/ga/Documents/CORRECTED_Q3_Data.csv

# ============================================================
# 3. Upload the flawed data to WordPress
# ============================================================
echo "Uploading flawed data to WordPress..."
cd /var/www/html/wordpress

# Clean up any previous runs
wp post delete $(wp post list --post_type=attachment --format=ids --allow-root 2>/dev/null) --force --allow-root 2>/dev/null || true
wp post delete $(wp post list --post_type=post --format=ids --allow-root 2>/dev/null) --force --allow-root 2>/dev/null || true

# Import media
MEDIA_OUTPUT=$(wp media import /tmp/pr_data/Q3-2024-Financial-Data.csv --title="Q3 2024 Financial Data" --porcelain --allow-root)
MEDIA_ID=$(echo "$MEDIA_OUTPUT" | tail -n 1)

# Get the exact relative path and save it for the verifier
MEDIA_PATH=$(wp post meta get "$MEDIA_ID" _wp_attached_file --allow-root)
echo "$MEDIA_PATH" > /tmp/original_media_path.txt
chmod 666 /tmp/original_media_path.txt
MEDIA_URL="http://localhost/wp-content/uploads/$MEDIA_PATH"

# ============================================================
# 4. Create the original announcement post
# ============================================================
echo "Creating the original announcement post..."
wp post create --post_type=post --post_status=publish \
    --post_title="Q3 2024 Financial Results Announced" \
    --post_content="<!-- wp:paragraph --><p>We are proud to announce our Q3 2024 financial results. It has been a record quarter.</p><!-- /wp:paragraph --><!-- wp:paragraph --><p><a href=\"$MEDIA_URL\">Download Full Financial Data (CSV)</a></p><!-- /wp:paragraph -->" \
    --post_author=1 --allow-root > /tmp/original_post_id.txt

# Ensure the tag exists so it's easy to add
wp term create post_tag "Press Release" --allow-root 2>/dev/null || true

# ============================================================
# 5. Launch and Setup Firefox
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Original media path: $MEDIA_PATH"