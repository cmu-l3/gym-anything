#!/bin/bash
echo "=== Setting up restructure_product_catalog_hierarchy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing categories that might clash with our test
echo "Cleaning up potential conflicting categories..."
suitecrm_db_query "UPDATE aos_product_categories SET deleted=1 WHERE name IN ('Smart Home Technologies', 'Security', 'Automation', 'Cameras', 'Sensors');"

# 2. Inject target products with NO category assigned (simulate disorganized state)
echo "Injecting uncategorized products..."
# Delete if they exist
suitecrm_db_query "DELETE FROM aos_products WHERE id IN ('prod-wifi-cam-0000-000000000001', 'prod-motion-sen-0000-000000000001', 'prod-smart-hub-0000-000000000001');"

# Insert products (aos_product_category_id is left empty)
suitecrm_db_query "INSERT INTO aos_products (id, name, date_entered, date_modified, modified_user_id, created_by, description, deleted, aos_product_category_id) VALUES 
('prod-wifi-cam-0000-000000000001', 'WiFi Doorbell Camera 4K', NOW(), NOW(), '1', '1', 'High definition smart doorbell with night vision.', 0, ''),
('prod-motion-sen-0000-000000000001', 'Motion Sensor Pro', NOW(), NOW(), '1', '1', 'Wireless PIR motion sensor for smart home systems.', 0, ''),
('prod-smart-hub-0000-000000000001', 'Smart Hub Controller', NOW(), NOW(), '1', '1', 'Central control hub for all home automation devices.', 0, '');"

# 3. Ensure logged in and navigate to Home dashboard
echo "Ensuring user is logged in..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 4

# 4. Take initial screenshot
echo "Taking initial screenshot..."
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="