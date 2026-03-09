#!/bin/bash
set -e
echo "=== Setting up add_drug_inventory task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Wait for LibreHealth EHR to be accessible
wait_for_librehealth 120

# Ensure drugs table exists (should exist from NHANES import schema)
docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e \
    "CREATE TABLE IF NOT EXISTS drugs (
        drug_id int NOT NULL AUTO_INCREMENT,
        name varchar(255) DEFAULT NULL,
        ndc_number varchar(20) DEFAULT NULL,
        on_order int DEFAULT 0,
        reorder_point float DEFAULT 0,
        max_level float DEFAULT 0,
        form int DEFAULT 0,
        size float DEFAULT 0,
        unit int DEFAULT 0,
        route int DEFAULT 0,
        substitute int DEFAULT 0,
        related_code varchar(255) DEFAULT NULL,
        cyp_factor float DEFAULT 0,
        active int DEFAULT 1,
        allow_combining int DEFAULT 0,
        allow_multiple int DEFAULT 0,
        drug_code varchar(25) DEFAULT NULL,
        consumable int DEFAULT 0,
        PRIMARY KEY (drug_id)
    )" 2>/dev/null || true

# Clean state: remove any existing Metformin entries to ensure fresh entry
echo "Cleaning previous Metformin entries..."
docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -e \
    "DELETE FROM drug_inventory WHERE drug_id IN (SELECT drug_id FROM drugs WHERE LOWER(name) LIKE '%metformin%')" 2>/dev/null || true
docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -e \
    "DELETE FROM drug_templates WHERE drug_id IN (SELECT drug_id FROM drugs WHERE LOWER(name) LIKE '%metformin%')" 2>/dev/null || true
docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -e \
    "DELETE FROM drugs WHERE LOWER(name) LIKE '%metformin%'" 2>/dev/null || true

# Record initial drug count (after cleanup)
INITIAL_COUNT=$(docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e \
    "SELECT COUNT(*) FROM drugs" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_drug_count.txt
echo "Initial drug count: $INITIAL_COUNT"

# Restart Firefox at login page with clean state
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"
sleep 3

# Wait for Firefox to fully load
wait_for_window "firefox\|mozilla\|LibreHealth\|Login" 30

# Focus and maximize
WID=$(get_firefox_wid)
focus_and_maximize "$WID"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="