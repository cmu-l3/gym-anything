#!/bin/bash
set -e
echo "=== Setting up classify_hotel_markets task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# 1. Ensure 'demodb' exists and has basic schema
# (The environment setup usually handles this, but we double check)
if ! orientdb_db_exists "demodb"; then
    echo "Creating demodb..."
    # We rely on the seed script if db is missing, but usually it's there.
    # If missing, we might fail or try to run seed. 
    # For this task, we assume the env hook ran.
    echo "Warning: demodb not found, attempting to run seed..."
    python3 /workspace/scripts/seed_demodb.py > /dev/null 2>&1
fi

# 2. Reset State: Drop 'Market' property if it exists
echo "Resetting schema: Dropping Market property if exists..."
orientdb_sql "demodb" "DROP PROPERTY Hotels.Market FORCE" > /dev/null 2>&1 || true

# 3. Ensure Deterministic Data
# We need specific hotels to have specific visitors to guarantee International vs Domestic results.
# We will clear edges for specific hotels and re-insert known patterns.

# Define test hotels (using Name to identify)
HOTEL_DOM="Hotel Artemide"       # Italy (Rome)
HOTEL_INT="The Plaza Hotel"      # USA (New York)
HOTEL_MIX="Park Hyatt Tokyo"     # Japan (Tokyo)

echo "Injecting deterministic test data..."

# Get RIDs for these hotels
RID_DOM=$(orientdb_sql "demodb" "SELECT @rid FROM Hotels WHERE Name='$HOTEL_DOM'" | jq -r '.result[0].rid')
RID_INT=$(orientdb_sql "demodb" "SELECT @rid FROM Hotels WHERE Name='$HOTEL_INT'" | jq -r '.result[0].rid')
RID_MIX=$(orientdb_sql "demodb" "SELECT @rid FROM Hotels WHERE Name='$HOTEL_MIX'" | jq -r '.result[0].rid')

# Get RIDs for profiles (Nationality)
# Luca (Italian)
RID_IT=$(orientdb_sql "demodb" "SELECT @rid FROM Profiles WHERE Name='Luca' AND Nationality='Italian'" | jq -r '.result[0].rid')
# John (American)
RID_US=$(orientdb_sql "demodb" "SELECT @rid FROM Profiles WHERE Name='John' AND Nationality='American'" | jq -r '.result[0].rid')
# Yuki (Japanese)
RID_JP=$(orientdb_sql "demodb" "SELECT @rid FROM Profiles WHERE Name='Yuki' AND Nationality='Japanese'" | jq -r '.result[0].rid')
# Sophie (French)
RID_FR=$(orientdb_sql "demodb" "SELECT @rid FROM Profiles WHERE Name='Sophie' AND Nationality='French'" | jq -r '.result[0].rid')

# Function to clear stays for a hotel
clear_stays() {
    local h_rid="$1"
    # Delete edges where in = hotel
    orientdb_sql "demodb" "DELETE EDGE HasStayed WHERE in = $h_rid" > /dev/null 2>&1
}

# Function to add stay
add_stay() {
    local p_rid="$1"
    local h_rid="$2"
    orientdb_sql "demodb" "CREATE EDGE HasStayed FROM $p_rid TO $h_rid" > /dev/null 2>&1
}

if [ -n "$RID_DOM" ] && [ -n "$RID_IT" ]; then
    echo "Setting up Domestic case: $HOTEL_DOM (Italy) visited by Luca (Italian)"
    clear_stays "$RID_DOM"
    add_stay "$RID_IT" "$RID_DOM" # Same nationality -> Domestic
    add_stay "$RID_IT" "$RID_DOM"
fi

if [ -n "$RID_INT" ] && [ -n "$RID_US" ] && [ -n "$RID_FR" ]; then
    echo "Setting up International case: $HOTEL_INT (USA) visited by Sophie (French)"
    clear_stays "$RID_INT"
    add_stay "$RID_FR" "$RID_INT" # Different -> International
    add_stay "$RID_FR" "$RID_INT" 
fi

if [ -n "$RID_MIX" ] && [ -n "$RID_JP" ] && [ -n "$RID_US" ]; then
    echo "Setting up Mixed (International) case: $HOTEL_MIX (Japan) visited by Yuki (Japan) and John (US)"
    clear_stays "$RID_MIX"
    add_stay "$RID_JP" "$RID_MIX" # Same
    add_stay "$RID_US" "$RID_MIX" # Diff
    # Total 2, Diff 1. Ratio 0.5. Logic: >= 0.5 is International.
fi

# 4. Prepare UI
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="