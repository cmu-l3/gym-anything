#!/bin/bash
set -e
echo "=== Setting up link_asset_to_vendor task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Wait for Eramba DB to be ready
echo "Waiting for database..."
for i in {1..30}; do
    if docker exec eramba-db mysqladmin ping -h localhost -u root -peramba_root_pass 2>/dev/null | grep -q "alive"; then
        break
    fi
    sleep 1
done

# 3. Seed Required Data (Asset + Third Party)
echo "Seeding GRC data..."

# Create Asset: HR Employee Portal
# Note: Using INSERT IGNORE or checking existence to prevent duplicates
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO assets (name, description, asset_type_id, risk_classification_id, created, modified, deleted) 
     SELECT 'HR Employee Portal', 'SaaS portal for payroll and benefits', 1, 1, NOW(), NOW(), 0 
     WHERE NOT EXISTS (SELECT 1 FROM assets WHERE name = 'HR Employee Portal');" 2>/dev/null || echo "Asset creation failed or skipped"

# Create Third Party: Workday Inc.
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO third_parties (name, description, created, modified, deleted) 
     SELECT 'Workday Inc.', 'HR and Finance SaaS Provider', NOW(), NOW(), 0 
     WHERE NOT EXISTS (SELECT 1 FROM third_parties WHERE name = 'Workday Inc.');" 2>/dev/null || echo "Third Party creation failed or skipped"

# 4. Clear any existing link between them (Ensure clean state)
# We need to find the IDs first to be safe, then delete from the join table.
# Eramba typically uses 'assets_third_parties' for this relationship.
echo "Clearing existing associations..."
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "DELETE FROM assets_third_parties 
     WHERE asset_id IN (SELECT id FROM assets WHERE name='HR Employee Portal') 
     AND third_party_id IN (SELECT id FROM third_parties WHERE name='Workday Inc.');" 2>/dev/null || echo "No existing link to clear"

# 5. Prepare Application State
# Ensure Firefox is running and logged in
ensure_firefox_eramba "http://localhost:8080/assets/index"

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Data seeded: Asset 'HR Employee Portal' and Vendor 'Workday Inc.'"
echo "Link cleared. Ready for agent."