#!/bin/bash
echo "=== Setting up migrate_hotel_type_to_tags task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# 1. Reset Schema: Ensure 'Tags' does not exist and 'Type' does
echo "Resetting Hotels schema..."

# Check if Tags exists
if orientdb_class_exists "demodb" "Hotels"; then
    # Drop Tags property if it exists
    orientdb_sql "demodb" "DROP PROPERTY Hotels.Tags FORCE" > /dev/null 2>&1 || true
    
    # Ensure Type property exists
    # We create it just in case it was dropped in a previous run
    orientdb_sql "demodb" "CREATE PROPERTY Hotels.Type STRING" > /dev/null 2>&1 || true
fi

# 2. Seed Data: Ensure specific test cases exist with known initial states
echo "Seeding test data..."

# Helper to safely update/insert specific hotels
seed_hotel() {
    local name="$1"
    local type="$2"
    # Try to update first
    local res
    res=$(orientdb_sql "demodb" "UPDATE Hotels SET Type='$type' WHERE Name='$name'")
    # If 0 updated, insert
    local count
    count=$(echo "$res" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', [{}])[0].get('count', 0))" 2>/dev/null || echo "0")
    
    if [ "$count" = "0" ]; then
        echo "  Inserting '$name' ($type)..."
        orientdb_sql "demodb" "INSERT INTO Hotels SET Name='$name', Type='$type', City='SeedCity', Country='SeedCountry'" > /dev/null 2>&1
    else
        echo "  Updated '$name' to Type='$type'"
    fi
}

seed_hotel "Copacabana Palace" "Historic"
seed_hotel "Terme di Saturnia Spa" "Luxury"
seed_hotel "Hotel Artemide" "Boutique"
seed_hotel "Tivoli Ecoresort Praia do Forte" "Resort"

# 3. Launch Firefox to Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="