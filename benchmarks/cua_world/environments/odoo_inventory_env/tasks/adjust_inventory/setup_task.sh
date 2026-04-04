#!/bin/bash
# Setup script for Adjust Inventory task
# Records initial stock levels and ensures test product exists

echo "=== Setting up Adjust Inventory task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
echo $(date +%s) > /tmp/task_start_time.txt

# Record initial stock quant count
INITIAL_QUANT_COUNT=$(get_stock_quant_count)
echo "$INITIAL_QUANT_COUNT" > /tmp/initial_quant_count.txt
echo "Initial quant count: $INITIAL_QUANT_COUNT"

# Get the stock location ID
STOCK_LOCATION=$(odoo_query "SELECT id FROM stock_location WHERE complete_name LIKE '%/Stock' AND usage = 'internal' LIMIT 1")
echo "$STOCK_LOCATION" > /tmp/stock_location_id.txt
echo "Stock location ID: $STOCK_LOCATION"

# Find a storable product with current stock that's NOT 50
echo ""
echo "Finding a product with stock quantity != 50..."

PRODUCT_WITH_STOCK=$(odoo_query_rows "SELECT sq.product_id, pt.name, sq.quantity, sq.location_id
                                      FROM stock_quant sq
                                      JOIN product_product pp ON sq.product_id = pp.id
                                      JOIN product_template pt ON pp.product_tmpl_id = pt.id
                                      WHERE sq.location_id = $STOCK_LOCATION
                                        AND sq.quantity > 0
                                        AND sq.quantity != 50
                                      ORDER BY sq.quantity DESC
                                      LIMIT 1")

if [ -z "$PRODUCT_WITH_STOCK" ]; then
    echo "No suitable product found. Creating test product with stock..."

    # Create a product template
    odoo_query "INSERT INTO product_template (name, detailed_type, list_price, standard_price, active, sale_ok, purchase_ok, create_date, write_date)
                VALUES ('Inventory Test Product', 'product', 30.00, 20.00, true, true, true, NOW(), NOW())
                ON CONFLICT DO NOTHING"

    # Get the product.product ID
    TEST_PRODUCT=$(odoo_query "SELECT pp.id FROM product_product pp
                               JOIN product_template pt ON pp.product_tmpl_id = pt.id
                               WHERE pt.name = 'Inventory Test Product' LIMIT 1")

    if [ -n "$TEST_PRODUCT" ]; then
        # Add some initial stock (not 50)
        odoo_query "INSERT INTO stock_quant (product_id, location_id, quantity, reserved_quantity, create_date, write_date)
                    VALUES ($TEST_PRODUCT, $STOCK_LOCATION, 25.0, 0.0, NOW(), NOW())
                    ON CONFLICT (product_id, location_id) DO UPDATE SET quantity = 25.0"

        PRODUCT_WITH_STOCK=$(odoo_query_rows "SELECT sq.product_id, 'Inventory Test Product' as name, sq.quantity, sq.location_id
                                              FROM stock_quant sq
                                              WHERE sq.product_id = $TEST_PRODUCT AND sq.location_id = $STOCK_LOCATION")
    fi
fi

if [ -n "$PRODUCT_WITH_STOCK" ]; then
    TARGET_PRODUCT_ID=$(echo "$PRODUCT_WITH_STOCK" | cut -f1)
    TARGET_PRODUCT_NAME=$(echo "$PRODUCT_WITH_STOCK" | cut -f2)
    INITIAL_QUANTITY=$(echo "$PRODUCT_WITH_STOCK" | cut -f3)
    LOCATION_ID=$(echo "$PRODUCT_WITH_STOCK" | cut -f4)

    echo ""
    echo "Target product for adjustment:"
    echo "  Product ID: $TARGET_PRODUCT_ID"
    echo "  Name: $TARGET_PRODUCT_NAME"
    echo "  Current quantity: $INITIAL_QUANTITY"
    echo "  Location ID: $LOCATION_ID"

    echo "$TARGET_PRODUCT_ID" > /tmp/target_product_id.txt
    echo "$TARGET_PRODUCT_NAME" > /tmp/target_product_name.txt
    echo "$INITIAL_QUANTITY" > /tmp/initial_quantity.txt
else
    echo "WARNING: Could not find or create a test product for inventory adjustment"
fi

# Record all current stock levels for comparison
echo ""
echo "Recording all current stock levels..."
odoo_query "SELECT sq.product_id, pt.name, sq.quantity FROM stock_quant sq
            JOIN product_product pp ON sq.product_id = pp.id
            JOIN product_template pt ON pp.product_tmpl_id = pt.id
            WHERE sq.location_id = $STOCK_LOCATION
            ORDER BY sq.quantity DESC LIMIT 20" > /tmp/initial_stock_levels.txt

# Get max quant ID for detecting new quants
MAX_QUANT_ID=$(odoo_query "SELECT COALESCE(MAX(id), 0) FROM stock_quant")
echo "$MAX_QUANT_ID" > /tmp/max_quant_id.txt
echo "Max quant ID before task: $MAX_QUANT_ID"

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
echo "Task: Adjust inventory of a product to exactly 50 units"
echo "Reference: Annual Stock Count"

# Display the target product name in a way the agent can see
# Create a text file with task info and open it in a new Firefox tab
TASK_INFO_FILE="/tmp/task_info.html"
cat > "$TASK_INFO_FILE" << EOF
<!DOCTYPE html>
<html>
<head><title>Task Information</title></head>
<body style="font-family: Arial, sans-serif; padding: 40px; background: #f0f0f0;">
<h1 style="color: #333;">Adjust Inventory Task</h1>
<div style="background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 5px rgba(0,0,0,0.1);">
<h2 style="color: #007bff;">Target Product</h2>
<p style="font-size: 24px; font-weight: bold; color: #dc3545;">$TARGET_PRODUCT_NAME</p>
<h2 style="color: #007bff;">Instructions</h2>
<ol style="font-size: 16px; line-height: 1.8;">
<li>Log in to Odoo with admin/admin</li>
<li>Navigate to Inventory module</li>
<li>Find and select the product: <strong>$TARGET_PRODUCT_NAME</strong></li>
<li>Adjust its quantity to <strong>exactly 50 units</strong></li>
<li>Enter reason: <strong>Annual Stock Count</strong></li>
<li>Apply/Validate the adjustment</li>
</ol>
<p style="color: #6c757d; font-size: 14px;">Current quantity: $INITIAL_QUANTITY units</p>
</div>
</body>
</html>
EOF

# Open the task info page in Firefox
echo "Opening task information in Firefox..."
su - ga -c "DISPLAY=:1 firefox 'file://$TASK_INFO_FILE' &" 2>/dev/null
sleep 2

# Switch back to Odoo tab
su - ga -c "DISPLAY=:1 xdotool key ctrl+1" 2>/dev/null || true
sleep 1
