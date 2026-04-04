#!/bin/bash
# Setup script for Create Product task
# Records initial state before task execution

echo "=== Setting up Create Product task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
echo $(date +%s) > /tmp/task_start_time.txt

# Record initial product count
INITIAL_PRODUCT_COUNT=$(get_product_count)
echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count.txt
echo "Initial product count: $INITIAL_PRODUCT_COUNT"

# Get maximum product ID before task
MAX_PRODUCT_ID=$(odoo_query "SELECT COALESCE(MAX(id), 0) FROM product_template")
echo "$MAX_PRODUCT_ID" > /tmp/max_product_id.txt
echo "Max product ID before task: $MAX_PRODUCT_ID"

# Check if the target product already exists (it shouldn't)
# Odoo 17 stores name as JSONB: {"en_US": "Product Name"}
TARGET_NAME="Industrial Safety Helmet"
TARGET_REF="HELM-IND-001"

EXISTING_BY_NAME=$(odoo_query "SELECT id FROM product_template WHERE LOWER(name->>'en_US') = LOWER('$TARGET_NAME') LIMIT 1")
EXISTING_BY_REF=$(odoo_query "SELECT id FROM product_template WHERE default_code = '$TARGET_REF' LIMIT 1")

if [ -n "$EXISTING_BY_NAME" ] || [ -n "$EXISTING_BY_REF" ]; then
    echo "WARNING: Product '$TARGET_NAME' or ref '$TARGET_REF' already exists!"
    echo "  By name: $EXISTING_BY_NAME"
    echo "  By ref: $EXISTING_BY_REF"
    # Remove existing product to ensure clean test
    if [ -n "$EXISTING_BY_NAME" ]; then
        odoo_query "DELETE FROM product_template WHERE id = $EXISTING_BY_NAME" || true
    fi
    if [ -n "$EXISTING_BY_REF" ] && [ "$EXISTING_BY_REF" != "$EXISTING_BY_NAME" ]; then
        odoo_query "DELETE FROM product_template WHERE id = $EXISTING_BY_REF" || true
    fi
    echo "Existing product(s) removed for clean test"
fi

# Ensure Firefox is on the Odoo login page or main page
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
echo "Task: Create product '$TARGET_NAME' with internal reference '$TARGET_REF'"
