#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up update_records task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 120

# --- Record Initial State (Anti-Gaming) ---
# We verify the records exist and record their current values to ensure they actually change later.
echo "Recording initial state of target records..."

# Helper to extract value from SQL result
get_field_value() {
    local query="$1"
    local field="$2"
    orientdb_sql demodb "$query" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    r = d.get('result', [])
    if r:
        print(r[0].get('$field', 'MISSING'))
    else:
        print('NOT_FOUND')
except:
    print('ERROR')
" 2>/dev/null
}

# 1. Hotel Artemide (Stars)
INIT_STARS=$(get_field_value "SELECT Stars FROM Hotels WHERE Name='Hotel Artemide'" "Stars")
echo "  Hotel Artemide Stars: $INIT_STARS"

# 2. The Savoy (Phone)
INIT_PHONE=$(get_field_value "SELECT Phone FROM Hotels WHERE Name='The Savoy'" "Phone")
echo "  The Savoy Phone: $INIT_PHONE"

# 3. Copacabana Palace (Type)
INIT_TYPE=$(get_field_value "SELECT Type FROM Hotels WHERE Name='Copacabana Palace'" "Type")
echo "  Copacabana Palace Type: $INIT_TYPE"

# 4. Luca Rossi (Surname)
INIT_SURNAME=$(get_field_value "SELECT Surname FROM Profiles WHERE Email='luca.rossi@example.com'" "Surname")
echo "  luca.rossi Surname: $INIT_SURNAME"

# Record total counts to detect if agent just deletes everything
HOTEL_COUNT=$(get_field_value "SELECT COUNT(*) as cnt FROM Hotels" "cnt")
PROFILE_COUNT=$(get_field_value "SELECT COUNT(*) as cnt FROM Profiles" "cnt")

# Save initial state to JSON
cat > /tmp/initial_state.json << EOF
{
    "artemide_stars": "$INIT_STARS",
    "savoy_phone": "$INIT_PHONE",
    "copacabana_type": "$INIT_TYPE",
    "luca_surname": "$INIT_SURNAME",
    "hotel_count": $HOTEL_COUNT,
    "profile_count": $PROFILE_COUNT,
    "timestamp": $(date +%s)
}
EOF

# Ensure Firefox is open at OrientDB Studio
echo "Ensuring Firefox is at OrientDB Studio..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

sleep 3

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== update_records task setup complete ==="