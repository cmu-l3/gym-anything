#!/bin/bash
set -e
echo "=== Setting up task: expand_product_variations ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for database
for i in {1..30}; do
    if check_db_connection; then
        break
    fi
    sleep 2
done

echo "Cleaning up any previous state..."
# Find ID of Classic T-Shirt and delete if exists
OLD_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_title='Classic T-Shirt' AND post_type='product' LIMIT 1")
if [ -n "$OLD_ID" ]; then
    wp post delete $OLD_ID --force --allow-root
fi

# Create Global Attribute 'Color' if not exists
echo "Configuring attributes..."
if ! wp wc product_attribute list --allow-root | grep -q "Color"; then
    wp wc product_attribute create --name="Color" --slug="color" --type="select" --order_by="menu_order" --has_archives=true --allow-root
fi
ATTR_ID=$(wp wc product_attribute list --format=json --allow-root | jq '.[] | select(.slug=="color") | .id')

# Create Terms 'Red' and 'Blue'
# Ensure 'Black' does NOT exist to force agent to create it
echo "Setting up terms..."
wp wc product_attribute_term create $ATTR_ID --name="Red" --slug="red" --allow-root || true
wp wc product_attribute_term create $ATTR_ID --name="Blue" --slug="blue" --allow-root || true

BLACK_TERM_ID=$(wp wc product_attribute_term list $ATTR_ID --search="Black" --format=json --allow-root | jq '.[0].id')
if [ "$BLACK_TERM_ID" != "null" ] && [ -n "$BLACK_TERM_ID" ]; then
    wp wc product_attribute_term delete $ATTR_ID $BLACK_TERM_ID --force --allow-root
fi

# Create Variable Product 'Classic T-Shirt'
echo "Creating variable product..."
PROD_ID=$(wp wc product create --name="Classic T-Shirt" --type="variable" --status="publish" --description="A timeless classic." --user=admin --porcelain --allow-root)

# Assign Attributes (Red, Blue) to Product
# We use direct update to set attributes correctly for variable product
# Note: "options" list is limited to Red and Blue
wp wc product update $PROD_ID --attributes='[{"id":'$ATTR_ID',"visible":true,"variation":true,"options":["Red","Blue"]}]' --allow-root

# Create Variations for Red and Blue
echo "Creating initial variations..."
wp wc product_variation create $PROD_ID --attributes='[{"id":'$ATTR_ID',"option":"Red"}]' --regular_price="20.00" --sku="CTS-RED" --allow-root
wp wc product_variation create $PROD_ID --attributes='[{"id":'$ATTR_ID',"option":"Blue"}]' --regular_price="20.00" --sku="CTS-BLU" --allow-root

# Ensure WordPress admin is fully loaded
echo "Launching Firefox..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# Navigate to Products list
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=product' &"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "Setup complete. Product ID: $PROD_ID"