#!/bin/bash
set -e
echo "=== Setting up create_compliance_analysis task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Seed Database with PCI-DSS Data
# We need to ensure the Regulator, Package, and Item exist so the agent can select them.
echo "Seeding PCI-DSS Compliance Data..."

# Create Regulator if not exists
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO compliance_package_regulators (name, created, modified) \
     SELECT 'PCI Security Standards Council', NOW(), NOW() \
     WHERE NOT EXISTS (SELECT 1 FROM compliance_package_regulators WHERE name='PCI Security Standards Council');"

# Get Regulator ID
REG_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT id FROM compliance_package_regulators WHERE name='PCI Security Standards Council' LIMIT 1;")

# Create Package if not exists
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO compliance_packages (compliance_package_regulator_id, title, description, created, modified) \
     SELECT $REG_ID, 'PCI-DSS v4.0', 'Payment Card Industry Data Security Standard v4.0', NOW(), NOW() \
     WHERE NOT EXISTS (SELECT 1 FROM compliance_packages WHERE title='PCI-DSS v4.0');"

# Get Package ID
PKG_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT id FROM compliance_packages WHERE title='PCI-DSS v4.0' LIMIT 1;")

# Create Compliance Package Items (Requirements) if not exist
# We specifically need Req 6.3.3
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO compliance_package_items (compliance_package_id, item_id, title, description, created, modified) \
     SELECT $PKG_ID, '6.3.3', 'Req 6.3.3 - Install critical patches within one month of release', 'Ensure that all system components and software are protected from known vulnerabilities by installing applicable security patches/updates.', NOW(), NOW() \
     WHERE NOT EXISTS (SELECT 1 FROM compliance_package_items WHERE compliance_package_id=$PKG_ID AND item_id='6.3.3');"

# Create a few distractor items for realism
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO compliance_package_items (compliance_package_id, item_id, title, description, created, modified) \
     SELECT $PKG_ID, '1.2.1', 'Req 1.2.1 - Restrict inbound and outbound traffic', 'Restrict inbound and outbound traffic to that which is necessary for the cardholder data environment.', NOW(), NOW() \
     WHERE NOT EXISTS (SELECT 1 FROM compliance_package_items WHERE compliance_package_id=$PKG_ID AND item_id='1.2.1');"

echo "Database seeded with PCI-DSS v4.0 data."

# 3. Record initial count of compliance analyses
INITIAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM compliance_analyses;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# 4. Prepare UI
# Ensure Firefox is open and logged in
ensure_firefox_eramba "http://localhost:8080/compliance/compliance-analysis/index"
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="