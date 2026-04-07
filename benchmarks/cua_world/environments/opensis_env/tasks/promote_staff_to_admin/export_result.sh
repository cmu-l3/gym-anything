#!/bin/bash
set -euo pipefail

echo "=== Exporting Task Result ==="

# Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Query current state of Sarah Jenkins
echo "Querying database for Sarah Jenkins (ID 9001)..."

# 1. Check Login Authentication Profile ID
# Expected: 1 (Admin)
CURRENT_PROFILE_ID=$($MYSQL_CMD -N -e "SELECT profile_id FROM login_authentication WHERE user_id=9001" 2>/dev/null || echo "0")

# 2. Check OpenSIS Profile String
# Expected: 'admin'
CURRENT_OPENSIS_PROFILE=$($MYSQL_CMD -N -e "SELECT opensis_profile FROM staff_school_info WHERE staff_id=9001" 2>/dev/null || echo "none")

# 3. Check Staff Profile Text
# Expected: 'Administrator' or similar, though verifying the ID is more robust
CURRENT_STAFF_PROFILE=$($MYSQL_CMD -N -e "SELECT profile FROM staff WHERE staff_id=9001" 2>/dev/null || echo "none")

# 4. Check Initial State
INITIAL_PROFILE_ID=$(cat /tmp/initial_profile_id.txt 2>/dev/null || echo "0")

echo "Debug: Initial ID=$INITIAL_PROFILE_ID, Current ID=$CURRENT_PROFILE_ID, Profile=$CURRENT_OPENSIS_PROFILE"

# Create JSON result
# Using python for safe JSON generation
python3 -c "
import json
import time

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'target_user_id': 9001,
    'initial_profile_id': int('$INITIAL_PROFILE_ID'),
    'current_profile_id': int('$CURRENT_PROFILE_ID') if '$CURRENT_PROFILE_ID'.isdigit() else 0,
    'current_opensis_profile': '$CURRENT_OPENSIS_PROFILE',
    'current_staff_profile': '$CURRENT_STAFF_PROFILE',
    'screenshot_exists': True
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="