#!/bin/bash
# Task: create_product_variant
# Goal: Ensure Ekylibre is running, clean up any previous instance of the target product, and navigate to the creation page.

set -e
echo "=== Setting up create_product_variant task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Wait for Ekylibre to be ready
wait_for_ekylibre 180
EKYLIBRE_BASE=$(detect_ekylibre_url)

# 3. Cleanup: Remove existing 'Ammonitrate 33.5' variant if it exists from a previous run
# We use docker exec to run psql inside the db container.
echo "Cleaning up any existing 'Ammonitrate 33.5' records..."
docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -c "DELETE FROM product_nature_variants WHERE name ILIKE '%Ammonitrate 33.5%';" 2>/dev/null || true

# 4. Record initial count of variants
INITIAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM product_nature_variants")
echo "$INITIAL_COUNT" > /tmp/initial_variant_count.txt
echo "Initial product nature variants count: $INITIAL_COUNT"

# 5. Open Firefox to the Product Nature Variant creation page
# Path: /backend/product_nature_variants/new
TARGET_URL="${EKYLIBRE_BASE}/backend/product_nature_variants/new"
echo "Navigating to: $TARGET_URL"

ensure_firefox_with_ekylibre "$TARGET_URL"
sleep 5

# 6. Maximize window for better visibility
maximize_firefox

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="