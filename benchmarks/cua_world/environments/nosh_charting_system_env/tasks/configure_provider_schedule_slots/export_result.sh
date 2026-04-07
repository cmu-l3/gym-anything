#!/bin/bash
# Export script for Configure Provider Schedule Slots task
set -e

echo "=== Exporting Task Results ==="

# 1. Define constants
DB_USER="root"
DB_PASS="rootpassword"
DB_NAME="nosh"
TARGET_USER="demo_provider"

# 2. Get Task Timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Final Database State
# We need the schedule_increment for the target provider
echo "Querying final database state..."
FINAL_INCREMENT=$(docker exec nosh-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -N -e \
    "SELECT schedule_increment FROM providers WHERE id=(SELECT id FROM users WHERE username='${TARGET_USER}');" 2>/dev/null || echo "ERROR")

# Get Initial Value for comparison
INITIAL_INCREMENT=$(cat /tmp/initial_increment.txt 2>/dev/null || echo "0")

echo "Initial Increment: $INITIAL_INCREMENT"
echo "Final Increment: $FINAL_INCREMENT"

# 4. Check if Admin user settings were accidentally touched (Anti-gaming/Safety check)
# Check admin (id=1) increment to ensure it wasn't changed incorrectly
ADMIN_INCREMENT=$(docker exec nosh-db mysql -u$DB_USER -p$DB_PASS $DB_NAME -N -e \
    "SELECT schedule_increment FROM providers WHERE id=1;" 2>/dev/null || echo "0")

# 5. Capture Final Screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_user": "$TARGET_USER",
    "initial_increment": "$INITIAL_INCREMENT",
    "final_increment": "$FINAL_INCREMENT",
    "admin_increment": "$ADMIN_INCREMENT",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# 7. Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="