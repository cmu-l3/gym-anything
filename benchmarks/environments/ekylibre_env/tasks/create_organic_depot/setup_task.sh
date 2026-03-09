#!/bin/bash
echo "=== Setting up Create Organic Depot Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Wait for Ekylibre to be ready
wait_for_ekylibre 120

# Record initial state: check if 'Silo Bio 01' already exists (should be 0)
# We check the 'entities' table or 'products' depending on exact version schema, 
# but storage locations are usually Entities of type 'Depot' or similar in recent versions.
# We'll check the 'entities' table for name match.
echo "Recording initial database state..."
INITIAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM entities WHERE name ILIKE 'Silo Bio 01'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_depot_count.txt

# Ensure Firefox is running and logged in
# We start at the Inventory dashboard to be helpful, but not deep inside the settings
EKYLIBRE_URL=$(detect_ekylibre_url)
ensure_firefox_with_ekylibre "$EKYLIBRE_URL/backend/stocks"

# Maximize window
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="