#!/bin/bash
set -e
echo "=== Setting up task: standardize_product_attribute ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for database
for i in {1..30}; do
    if check_db_connection; then
        break
    fi
    sleep 2
done

# CRITICAL: Ensure WordPress admin is accessible
if ! ensure_wordpress_shown 60; then
    echo "FATAL: WordPress admin not loading."
    exit 1
fi

# 1. Create the Global Attribute "Color" (pa_color)
echo "Creating global attribute 'Color'..."
wp wc product_attribute create --name="Color" --slug="pa_color" --type="select" --order_by="menu_order" --has_archives=true --user=admin --allow-root > /dev/null 2>&1 || echo "Attribute might already exist"

# Get the attribute ID
ATTR_ID=$(wp wc product_attribute list --format=json --allow-root | jq '.[] | select(.slug=="pa_color") | .id')

# 2. Add term "Green" to global attribute
echo "Adding term 'Green'..."
if [ -n "$ATTR_ID" ]; then
    wp wc product_attribute_term create "$ATTR_ID" --name="Green" --slug="green" --user=admin --allow-root > /dev/null 2>&1 || echo "Term might already exist"
fi

# 3. Create the Product with "Messy" Data (Custom Attributes)
# We use Python to insert the serialized PHP array directly to avoid Bash escaping issues with serialization
echo "Creating product with messy attributes..."

python3 -c "
import pymysql
import time

# Connect to DB
conn = pymysql.connect(host='127.0.0.1', user='wordpress', password='wordpresspass', database='wordpress')
cursor = conn.cursor()

# 1. Create basic product post
cursor.execute(\"INSERT INTO wp_posts (post_author, post_date, post_date_gmt, post_content, post_title, post_status, post_name, post_type, to_ping, pinged, post_modified, post_modified_gmt, post_content_filtered, post_excerpt) VALUES (1, NOW(), NOW(), '', 'Eco-Friendly Sneaker', 'publish', 'eco-friendly-sneaker', 'product', '', '', NOW(), NOW(), '', '')\")
product_id = cursor.lastrowid
print(f'Created Product ID: {product_id}')

# 2. Save ID for export script
with open('/tmp/target_product_id.txt', 'w') as f:
    f.write(str(product_id))

# 3. Create the 'Bad' Attributes (Serialized PHP Array)
# Structure:
# - Color: Custom text (is_taxonomy=0)
# - Material: Custom text (is_taxonomy=0)
# Note: PHP serialization format is strict (s:5:\"Color\").
# We manually construct the serialized string for:
# array(
#   'color' => array('name'=>'Color', 'value'=>'Green', 'position'=>0, 'is_visible'=>1, 'is_variation'=>0, 'is_taxonomy'=>0),
#   'material' => array('name'=>'Material', 'value'=>'Recycled Canvas', 'position'=>1, 'is_visible'=>1, 'is_variation'=>0, 'is_taxonomy'=>0)
# )

serialized_attrs = 'a:2:{s:5:\"color\";a:6:{s:4:\"name\";s:5:\"Color\";s:5:\"value\";s:5:\"Green\";s:8:\"position\";i:0;s:10:\"is_visible\";i:1;s:12:\"is_variation\";i:0;s:11:\"is_taxonomy\";i:0;}s:8:\"material\";a:6:{s:4:\"name\";s:8:\"Material\";s:5:\"value\";s:15:\"Recycled Canvas\";s:8:\"position\";i:1;s:10:\"is_visible\";i:1;s:12:\"is_variation\";i:0;s:11:\"is_taxonomy\";i:0;}}'

# 4. Insert meta
cursor.execute(\"INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES (%s, '_product_attributes', %s)\", (product_id, serialized_attrs))
cursor.execute(\"INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES (%s, '_regular_price', '85.00')\", (product_id))
cursor.execute(\"INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES (%s, '_price', '85.00')\", (product_id))
cursor.execute(\"INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES (%s, '_sku', 'EFS-GRN-01')\", (product_id))

conn.commit()
conn.close()
"

# Set up browser
echo "Launching Firefox..."
if ! pgrep -f "firefox" > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost/wp-admin/edit.php?post_type=product &"
else
    # Reload or open new tab if already running
    su - ga -c "DISPLAY=:1 firefox -new-tab http://localhost/wp-admin/edit.php?post_type=product &"
fi

# Maximize and Focus
sleep 5
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="