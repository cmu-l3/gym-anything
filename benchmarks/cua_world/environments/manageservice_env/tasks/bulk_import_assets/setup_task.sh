#!/bin/bash
# Setup script for bulk_import_assets task

echo "=== Setting up Bulk Import Assets Task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure SDP is running
ensure_sdp_running

# 3. Prepare the CSV file on Desktop
echo "Creating CSV file..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/shipment_sf_2025.csv << 'EOF'
Inventory Tag,Model,Serial Number,Office,Invoice Date,Unit Price
DEV-SF-01,MacBook Pro 16,C02XG1J2K3L4,San Francisco,2025-05-10,2499.00
DEV-SF-02,MacBook Pro 16,C02XG5M6N7P8,San Francisco,2025-05-10,2499.00
DEV-SF-03,Dell XPS 15,HJ7K9L1,San Francisco,2025-05-12,1850.00
DEV-SF-04,MacBook Pro 16,C02XG9R0S1T2,San Francisco,2025-05-10,2499.00
DEV-SF-05,Dell XPS 15,MN2P3Q4,San Francisco,2025-05-12,1850.00
DEV-SF-06,MacBook Pro 16,C02XG3V4W5X6,San Francisco,2025-05-10,2499.00
DEV-SF-07,MacBook Pro 16,C02XG7Y8Z9A0,San Francisco,2025-05-10,2499.00
DEV-SF-08,Dell XPS 15,RS5T6U7,San Francisco,2025-05-12,1850.00
DEV-SF-09,MacBook Pro 16,C02XG1B2C3D4,San Francisco,2025-05-10,2499.00
DEV-SF-10,Dell XPS 15,VW8X9Y0,San Francisco,2025-05-12,1850.00
DEV-SF-11,MacBook Pro 16,C02XG5E6F7G8,San Francisco,2025-05-10,2499.00
DEV-SF-12,MacBook Pro 16,C02XG9H0I1J2,San Francisco,2025-05-10,2499.00
DEV-SF-13,Dell XPS 15,ZA1B2C3,San Francisco,2025-05-12,1850.00
DEV-SF-14,MacBook Pro 16,C02XG3K4L5M6,San Francisco,2025-05-10,2499.00
DEV-SF-15,MacBook Pro 16,C02XG7N8P9Q0,San Francisco,2025-05-10,2499.00
EOF
chmod 644 /home/ga/Desktop/shipment_sf_2025.csv
chown ga:ga /home/ga/Desktop/shipment_sf_2025.csv

# 4. Clean up previous attempts (delete assets with these names)
log "Cleaning up old assets..."
sdp_db_exec "DELETE FROM resource WHERE resourcename LIKE 'DEV-SF-%';"

# 5. Ensure Pre-requisites (Site & Products) exist in DB to prevent import errors
# Note: In a real environment, we'd insert into 'site', 'product', 'producttype'.
# Here we do a best-effort insertion or rely on default data.
# We will insert "San Francisco" into SiteDefinition if possible, but the schema is complex.
# Instead, we'll assume the agent might need to create them on the fly if they don't exist,
# OR we insert them if we know the schema. 
# For this task, we'll try to insert the Site to be helpful.
log "Pre-seeding Site 'San Francisco'..."
sdp_db_exec "INSERT INTO sitedefinition (siteid, sitename) VALUES (3001, 'San Francisco') ON CONFLICT (sitename) DO NOTHING;"

# 6. Launch Firefox to Assets page
log "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Asset.do"
sleep 5

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Import assets from /home/ga/Desktop/shipment_sf_2025.csv"