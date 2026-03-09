#!/bin/bash
# Setup script for Create Internal Transfer task
# Records initial state and ensures test product exists with stock

echo "=== Setting up Create Internal Transfer task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
echo $(date +%s) > /tmp/task_start_time.txt

# Record initial transfer count
INITIAL_PICKING_COUNT=$(get_stock_picking_count)
echo "$INITIAL_PICKING_COUNT" > /tmp/initial_picking_count.txt
echo "Initial transfer count: $INITIAL_PICKING_COUNT"

# Record initial stock move count
INITIAL_MOVE_COUNT=$(get_stock_move_count)
echo "$INITIAL_MOVE_COUNT" > /tmp/initial_move_count.txt
echo "Initial move count: $INITIAL_MOVE_COUNT"

# Get maximum picking ID before task
MAX_PICKING_ID=$(odoo_query "SELECT COALESCE(MAX(id), 0) FROM stock_picking")
echo "$MAX_PICKING_ID" > /tmp/max_picking_id.txt
echo "Max picking ID before task: $MAX_PICKING_ID"

# Ensure there's at least one storable product with inventory
# Check for demo products first
DEMO_PRODUCT=$(odoo_query "SELECT id FROM product_product WHERE detailed_type = 'product' LIMIT 1")

if [ -z "$DEMO_PRODUCT" ]; then
    echo "No storable products found. Creating a test product..."

    # Create a product template for testing
    odoo_query "INSERT INTO product_template (name, detailed_type, list_price, standard_price, active, sale_ok, purchase_ok, create_date, write_date)
                VALUES ('Test Transfer Product', 'product', 25.00, 15.00, true, true, true, NOW(), NOW())
                RETURNING id"

    # Get the product.product ID (auto-created from template)
    DEMO_PRODUCT=$(odoo_query "SELECT id FROM product_product WHERE detailed_type = 'product' ORDER BY id DESC LIMIT 1")
    echo "Created test product with ID: $DEMO_PRODUCT"
fi

echo "Demo storable product ID available: $DEMO_PRODUCT"
echo "$DEMO_PRODUCT" > /tmp/demo_product_id.txt

# Get the stock location for the warehouse
STOCK_LOCATION=$(odoo_query "SELECT id FROM stock_location WHERE complete_name LIKE '%/Stock' AND usage = 'internal' LIMIT 1")
echo "Stock location ID: $STOCK_LOCATION"
echo "$STOCK_LOCATION" > /tmp/stock_location_id.txt

# Check if there's stock for the demo product, if not add some
if [ -n "$DEMO_PRODUCT" ] && [ -n "$STOCK_LOCATION" ]; then
    CURRENT_STOCK=$(odoo_query "SELECT COALESCE(SUM(quantity), 0) FROM stock_quant WHERE product_id = $DEMO_PRODUCT AND location_id = $STOCK_LOCATION")
    echo "Current stock for test product: $CURRENT_STOCK"

    if [ "${CURRENT_STOCK:-0}" -lt 20 ]; then
        echo "Adding initial stock via inventory adjustment..."
        # Add stock via direct quant insertion (simulating inventory adjustment)
        odoo_query "INSERT INTO stock_quant (product_id, location_id, quantity, reserved_quantity, create_date, write_date)
                    VALUES ($DEMO_PRODUCT, $STOCK_LOCATION, 100.0, 0.0, NOW(), NOW())
                    ON CONFLICT (product_id, location_id) DO UPDATE SET quantity = stock_quant.quantity + 100" || true
        echo "Added 100 units of test product to stock"
    fi
fi

# Check for sub-location (Shelf 1 or similar)
SUB_LOCATION=$(odoo_query "SELECT id FROM stock_location WHERE (name LIKE 'Shelf%' OR complete_name LIKE '%/Shelf%') AND usage = 'internal' LIMIT 1")

if [ -z "$SUB_LOCATION" ]; then
    echo "No sub-location found. Creating 'Shelf 1'..."
    if [ -n "$STOCK_LOCATION" ]; then
        odoo_query "INSERT INTO stock_location (name, complete_name, usage, location_id, active, create_date, write_date)
                    VALUES ('Shelf 1', 'WH/Stock/Shelf 1', 'internal', $STOCK_LOCATION, true, NOW(), NOW())
                    RETURNING id"
        SUB_LOCATION=$(odoo_query "SELECT id FROM stock_location WHERE name = 'Shelf 1' AND usage = 'internal' LIMIT 1")
    fi
fi
echo "Sub-location ID: $SUB_LOCATION"
echo "$SUB_LOCATION" > /tmp/sub_location_id.txt

# Ensure Firefox is ready
FIREFOX_WID=$(get_firefox_window_id)
if [ -n "$FIREFOX_WID" ]; then
    DISPLAY=:1 wmctrl -ia "$FIREFOX_WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox window focused and maximized"
else
    echo "Starting Firefox with Odoo..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web/login' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create an internal transfer with reference 'TRANSFER-001'"
echo "Move at least 10 units between internal locations"
