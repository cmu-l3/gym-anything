#!/bin/bash
# Setup script for Bulk Product Import task

echo "=== Setting up Bulk Product Import Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# 1. Create the CSV file
echo "Creating supplier CSV file..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/supplier_kitchenware_catalog.csv << 'CSVEOF'
sku,store_view_code,attribute_set_code,product_type,categories,product_websites,name,description,short_description,weight,product_online,tax_class_name,visibility,price,qty,is_in_stock
KITCHEN-CF01,,Default,simple,"Default Category/Home & Garden",base,"Stainless Steel Coffee Maker","Premium coffee maker with programmable timer and thermal carafe.","Premium coffee maker",4.5,1,Taxable Goods,"Catalog, Search",89.99,75,1
KITCHEN-KN01,,Default,simple,"Default Category/Home & Garden",base,"Chef Knife Set 8-Piece","Professional grade high-carbon stainless steel knife set with wooden block.","Professional knife set",3.2,1,Taxable Goods,"Catalog, Search",149.99,40,1
KITCHEN-CB01,,Default,simple,"Default Category/Home & Garden",base,"Bamboo Cutting Board Large","Eco-friendly organic bamboo cutting board with juice groove.","Large bamboo cutting board",2.1,1,Taxable Goods,"Catalog, Search",34.99,120,1
KITCHEN-MP01,,Default,simple,"Default Category/Home & Garden",base,"Non-Stick Muffin Pan 12-Cup","Heavy-duty steel muffin pan with non-stick coating for easy release.","Non-stick 12-cup muffin pan",1.5,1,Taxable Goods,"Catalog, Search",24.99,200,1
KITCHEN-BL01,,Default,simple,"Default Category/Home & Garden",base,"High-Speed Blender 1200W","Powerful 1200W motor blender for smoothies, soups, and ice crushing.","1200W High-Speed Blender",6.8,1,Taxable Goods,"Catalog, Search",119.99,55,1
KITCHEN-TK01,,Default,simple,"Default Category/Home & Garden",base,"Electric Kettle Glass 1.7L","Fast-boiling borosilicate glass kettle with blue LED indicator.","1.7L Glass Electric Kettle",2.9,1,Taxable Goods,"Catalog, Search",44.99,90,1
KITCHEN-MS01,,Default,simple,"Default Category/Home & Garden",base,"Stainless Steel Mixing Bowl Set","Set of 5 nesting mixing bowls with non-slip silicone bottoms.","Set of 5 mixing bowls",3.5,1,Taxable Goods,"Catalog, Search",39.99,110,1
KITCHEN-SP01,,Default,simple,"Default Category/Home & Garden",base,"Silicone Spatula Set 5-Piece","Heat-resistant silicone spatulas with reinforced steel core.","5-piece spatula set",0.8,1,Taxable Goods,"Catalog, Search",18.99,250,1
KITCHEN-CS01,,Default,simple,"Default Category/Home & Garden",base,"Cast Iron Skillet 12-inch","Pre-seasoned cast iron skillet for superior heat retention and cooking.","12-inch Cast Iron Skillet",7.5,1,Taxable Goods,"Catalog, Search",54.99,65,1
KITCHEN-RC01,,Default,simple,"Default Category/Home & Garden",base,"Digital Rice Cooker 6-Cup","Programmable rice cooker with steamer basket and keep-warm function.","6-Cup Digital Rice Cooker",4.2,1,Taxable Goods,"Catalog, Search",69.99,80,1
KITCHEN-TP01,,Default,simple,"Default Category/Home & Garden",base,"Ceramic Teapot with Infuser","Elegant ceramic teapot with stainless steel loose leaf tea infuser.","Ceramic Teapot",1.8,1,Taxable Goods,"Catalog, Search",29.99,130,1
KITCHEN-WK01,,Default,simple,"Default Category/Home & Garden",base,"Carbon Steel Wok 14-inch","Traditional carbon steel wok with flat bottom for electric or gas stoves.","14-inch Carbon Steel Wok",3.9,1,Taxable Goods,"Catalog, Search",42.99,70,1
CSVEOF

# Set permissions
chown ga:ga /home/ga/Documents/supplier_kitchenware_catalog.csv
chmod 644 /home/ga/Documents/supplier_kitchenware_catalog.csv

# 2. Record initial state (check if these SKUs already exist - should be 0)
echo "Checking for pre-existing KITCHEN SKUs..."
EXISTING_KITCHEN_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_entity WHERE sku LIKE 'KITCHEN-%'" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "$EXISTING_KITCHEN_COUNT" > /tmp/initial_kitchen_count
echo "Initial KITCHEN SKU count: ${EXISTING_KITCHEN_COUNT:-0}"

# 3. Ensure Firefox is running and logged in
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="
echo ""
echo "Task: Import products from CSV"
echo "File: /home/ga/Documents/supplier_kitchenware_catalog.csv"
echo "Magento Admin: System > Data Transfer > Import"
echo ""