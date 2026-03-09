#!/bin/bash
echo "=== Exporting delete_watchlist results ==="

JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_BASE="${JSTOCK_DATA_DIR}/watchlist"

# Take final screenshot before closing
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final_state.png" 2>/dev/null || true

# Close JStock gracefully to ensure filesystem sync
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key alt+F4" 2>/dev/null || true
sleep 2
# Confirm any "Save" or "Exit" dialogs
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 5

# Force kill if still running
pkill -f "jstock" 2>/dev/null || true

# Check specific directories
ENERGY_EXISTS="false"
if [ -d "${WATCHLIST_BASE}/Energy Stocks" ]; then
    ENERGY_EXISTS="true"
fi

MY_WATCHLIST_EXISTS="false"
if [ -d "${WATCHLIST_BASE}/My Watchlist" ]; then
    MY_WATCHLIST_EXISTS="true"
fi

TECH_EXISTS="false"
if [ -d "${WATCHLIST_BASE}/Tech Stocks" ]; then
    TECH_EXISTS="true"
fi

# Count remaining watchlists
REMAINING_COUNT=$(find "${WATCHLIST_BASE}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
INITIAL_COUNT=$(cat /tmp/initial_watchlist_count.txt 2>/dev/null || echo "3")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "energy_stocks_exists": $ENERGY_EXISTS,
    "my_watchlist_exists": $MY_WATCHLIST_EXISTS,
    "tech_stocks_exists": $TECH_EXISTS,
    "initial_count": $INITIAL_COUNT,
    "remaining_count": $REMAINING_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json