#!/bin/bash
echo "=== Setting up Query Optimization Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running and ready
wait_for_orientdb 60

echo "Preparing database state..."

# Function to safely drop an index if it exists
drop_index_safe() {
    local db=$1
    local index_name=$2
    if orientdb_index_exists "$db" "$index_name"; then
        echo "  Dropping existing index: $index_name"
        orientdb_sql "$db" "DROP INDEX $index_name" > /dev/null 2>&1
    fi
}

# 1. Ensure clean slate: Remove indexes that might solve the task
# We check for common names and property-based automatic names
# Hotels.City
drop_index_safe "demodb" "Hotels.City"
drop_index_safe "demodb" "Hotels_City_idx"
# Hotels.Country (part of composite)
drop_index_safe "demodb" "Hotels.Country"
drop_index_safe "demodb" "Hotels_Country_idx"
# Hotels.Stars (part of composite)
drop_index_safe "demodb" "Hotels.Stars"
# Hotels composite
drop_index_safe "demodb" "Hotels_Country_Stars"
drop_index_safe "demodb" "Hotels_Country_Stars_idx"
# Profiles.Nationality
drop_index_safe "demodb" "Profiles.Nationality"
drop_index_safe "demodb" "Profiles_Nationality_idx"

echo "Database indexes cleared for target fields."

# Record initial index count (should be baseline without the task indexes)
INITIAL_INDEXES=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" 2>/dev/null | \
    python3 -c "import json, sys; d=json.load(sys.stdin); print(sum(len(c.get('indexes', [])) for c in d.get('classes', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_INDEXES" > /tmp/initial_index_count.txt

# Remove any previous report file
rm -f /home/ga/query_optimization_report.txt

# Launch Firefox to OrientDB Studio (Studio handles login redirection usually, but we go to index)
echo "Launching Firefox to OrientDB Studio..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="