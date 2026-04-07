#!/bin/bash
# Setup script for execute_woocommerce_bulk_price_update task
# Installs WooCommerce, generates 25 categorised products with baseline prices

echo "=== Setting up execute_woocommerce_bulk_price_update task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

cd /var/www/html/wordpress

# ============================================================
# 1. Install and Activate WooCommerce
# ============================================================
echo "Installing and activating WooCommerce..."
if ! wp plugin is-active woocommerce --allow-root 2>/dev/null; then
    wp plugin install woocommerce --activate --allow-root 2>&1 || {
        echo "Failed to install via WP-CLI, downloading manually..."
        cd /var/www/html/wordpress/wp-content/plugins
        curl -sL "https://downloads.wordpress.org/plugin/woocommerce.latest-stable.zip" -o wc.zip
        unzip -qo wc.zip
        rm wc.zip
        chown -R www-data:www-data woocommerce
        cd /var/www/html/wordpress
        wp plugin activate woocommerce --allow-root
    }
fi

# Dismiss WooCommerce onboarding wizards
wp option update woocommerce_task_list_hidden "yes" --allow-root
wp option update woocommerce_onboarding_profile "{\"completed\":true}" --json --allow-root

# ============================================================
# 2. Clean Existing Products and Categories
# ============================================================
echo "Cleaning existing catalog..."
EXISTING_PIDS=$(wp post list --post_type=product --format=ids --allow-root 2>/dev/null)
if [ -n "$EXISTING_PIDS" ]; then
    wp post delete $EXISTING_PIDS --force --allow-root >/dev/null 2>&1
fi

# ============================================================
# 3. Generate Catalog using Python & WP-CLI
# ============================================================
echo "Generating catalog (25 products)..."

cat << 'EOF' > /tmp/create_catalog.py
import subprocess
import json

products = [
    {"name": "Ethiopian Yirgacheffe", "cat": "Coffee Beans", "price": 20.0},
    {"name": "Colombian Supremo", "cat": "Coffee Beans", "price": 15.0},
    {"name": "Sumatra Mandheling", "cat": "Coffee Beans", "price": 25.0},
    {"name": "Guatemala Antigua", "cat": "Coffee Beans", "price": 30.0},
    {"name": "Costa Rica Tarrazu", "cat": "Coffee Beans", "price": 35.0},
    {"name": "Kenya AA", "cat": "Coffee Beans", "price": 40.0},
    {"name": "Jamaica Blue Mountain", "cat": "Coffee Beans", "price": 55.0},
    {"name": "Hawaii Kona", "cat": "Coffee Beans", "price": 45.0},
    {"name": "Tanzania Peaberry", "cat": "Coffee Beans", "price": 10.0},
    {"name": "Brazil Santos", "cat": "Coffee Beans", "price": 50.0},

    {"name": "Chemex 8-Cup", "cat": "Brewing Equipment", "price": 45.0},
    {"name": "Hario V60", "cat": "Brewing Equipment", "price": 25.0},
    {"name": "AeroPress", "cat": "Brewing Equipment", "price": 30.0},
    {"name": "French Press 34oz", "cat": "Brewing Equipment", "price": 35.0},
    {"name": "Digital Scale", "cat": "Brewing Equipment", "price": 55.0},
    {"name": "Gooseneck Kettle", "cat": "Brewing Equipment", "price": 65.0},
    {"name": "Burr Grinder", "cat": "Brewing Equipment", "price": 145.0},
    {"name": "Cold Brew Maker", "cat": "Brewing Equipment", "price": 40.0},
    {"name": "Espresso Machine", "cat": "Brewing Equipment", "price": 215.0},
    {"name": "Moka Pot", "cat": "Brewing Equipment", "price": 50.0},

    {"name": "Logo T-Shirt", "cat": "Merchandise", "price": 20.0},
    {"name": "Ceramic Mug", "cat": "Merchandise", "price": 15.0},
    {"name": "Travel Tumbler", "cat": "Merchandise", "price": 25.0},
    {"name": "Tote Bag", "cat": "Merchandise", "price": 12.0},
    {"name": "Dad Hat", "cat": "Merchandise", "price": 18.0}
]

# Create Categories
for cat in ["Coffee Beans", "Brewing Equipment", "Merchandise"]:
    subprocess.run(f"wp term create product_cat '{cat}' --allow-root", shell=True, capture_output=True)

baseline = {}

for p in products:
    # Create product
    res = subprocess.run(f"wp post create --post_type=product --post_title='{p['name']}' --post_status=publish --porcelain --allow-root", shell=True, capture_output=True, text=True)
    pid = res.stdout.strip()

    # Set Category
    subprocess.run(f"wp post term set {pid} product_cat '{p['cat']}' --allow-root", shell=True, capture_output=True)

    # Set Price
    subprocess.run(f"wp post meta set {pid} _regular_price '{p['price']}' --allow-root", shell=True, capture_output=True)
    subprocess.run(f"wp post meta set {pid} _price '{p['price']}' --allow-root", shell=True, capture_output=True)

    baseline[pid] = {
        "name": p['name'],
        "cat": p['cat'],
        "initial_price": p['price']
    }

with open('/tmp/baseline_products.json', 'w') as f:
    json.dump(baseline, f, indent=2)
EOF

python3 /tmp/create_catalog.py
chmod 666 /tmp/baseline_products.json
echo "Catalog generation complete."

# ============================================================
# 4. Launch Firefox directly to Products page
# ============================================================
echo "Ensuring Firefox is running..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=product' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Maximize and Focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png
echo "=== Setup complete ==="