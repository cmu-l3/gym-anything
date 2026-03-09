#!/bin/bash
echo "=== Setting up Corporate Acquisition Rebranding task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure OrientDB is ready
wait_for_orientdb 120

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Resetting database state to ensure clean start..."

# 1. Revert any previous runs of this task
# Update hotels back to original state if they have the suffix
orientdb_sql "demodb" "UPDATE Hotels SET Name = Name.replace(' - The Collections', ''), Type = 'Boutique' WHERE Name LIKE '% - The Collections'" > /dev/null 2>&1

# 2. Drop created classes if they exist
# Drop BelongsTo edge class
if orientdb_class_exists "demodb" "BelongsTo"; then
    echo "Dropping existing BelongsTo class..."
    orientdb_sql "demodb" "DROP CLASS BelongsTo UNSAFE" > /dev/null 2>&1
fi

# Drop Brands vertex class
if orientdb_class_exists "demodb" "Brands"; then
    echo "Dropping existing Brands class..."
    orientdb_sql "demodb" "DROP CLASS Brands UNSAFE" > /dev/null 2>&1
fi

# 3. Verify specific Boutique hotels exist for the task
echo "Verifying target data..."
BOUTIQUE_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels WHERE Type='Boutique'" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

echo "Found $BOUTIQUE_COUNT Boutique hotels."

if [ "$BOUTIQUE_COUNT" -eq "0" ]; then
    echo "WARNING: No Boutique hotels found. Seeding minimal required data..."
    # Insert at least one Boutique hotel if missing
    orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Hotel Artemide', Type='Boutique', City='Rome', Country='Italy'" > /dev/null 2>&1
    echo "Inserted Hotel Artemide."
fi

# Record the initial count of Boutique hotels (this is our target count)
echo "$BOUTIQUE_COUNT" > /tmp/initial_boutique_count.txt

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="