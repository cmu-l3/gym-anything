#!/bin/bash
echo "=== Exporting add_school_rooms results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Database Data
# We need to export:
# - If the specific rooms exist (SCI-201, COMP-305) and their capacities
# - The final room count (to compare with initial)

# Get room data as JSON-like structure
ROOMS_DATA=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e \
    "SELECT title, capacity, syear FROM rooms WHERE school_id=1 AND title IN ('SCI-201', 'COMP-305');" 2>/dev/null)

# Parse Room 1 (SCI-201)
ROOM1_EXISTS="false"
ROOM1_CAP="0"
if echo "$ROOMS_DATA" | grep -i "SCI-201"; then
    ROOM1_EXISTS="true"
    ROOM1_CAP=$(echo "$ROOMS_DATA" | grep -i "SCI-201" | awk '{print $2}')
fi

# Parse Room 2 (COMP-305)
ROOM2_EXISTS="false"
ROOM2_CAP="0"
if echo "$ROOMS_DATA" | grep -i "COMP-305"; then
    ROOM2_EXISTS="true"
    ROOM2_CAP=$(echo "$ROOMS_DATA" | grep -i "COMP-305" | awk '{print $2}')
fi

# Get Counts
INITIAL_COUNT=$(cat /tmp/initial_room_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e \
    "SELECT COUNT(*) FROM rooms WHERE school_id=1;" 2>/dev/null || echo "0")

# Check Browser
BROWSER_RUNNING=$(pgrep -f "chrome|chromium" > /dev/null && echo "true" || echo "false")

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "room1": {
        "exists": $ROOM1_EXISTS,
        "capacity": "$ROOM1_CAP",
        "target_title": "SCI-201"
    },
    "room2": {
        "exists": $ROOM2_EXISTS,
        "capacity": "$ROOM2_CAP",
        "target_title": "COMP-305"
    },
    "counts": {
        "initial": ${INITIAL_COUNT:-0},
        "final": ${FINAL_COUNT:-0}
    },
    "browser_running": $BROWSER_RUNNING,
    "timestamp": "$(date +%s)"
}
EOF

# Safe move to /tmp/task_result.json
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json