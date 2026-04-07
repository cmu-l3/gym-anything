#!/bin/bash
# Export script for deactivate_user_account task

echo "=== Exporting Task Results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Database State
# We need to check:
# a) Does jdoe still exist? (Should be yes)
# b) Is jdoe active? (Should be no/0)
# c) Is admin still active? (Should be yes/1 - safety check)

echo "Querying database for user status..."

# Helper to run SQL
run_sql() {
    docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$1" 2>/dev/null
}

# Check JDOE
JDOE_EXISTS=$(run_sql "SELECT COUNT(*) FROM users WHERE username='jdoe'")
JDOE_ACTIVE=$(run_sql "SELECT active FROM users WHERE username='jdoe'")

# Check ADMIN (for safety)
ADMIN_ACTIVE=$(run_sql "SELECT active FROM users WHERE username='admin'")

# Check Timestamps/Logs (Anti-gaming)
# Check if the row was updated recently?
# NOSH might have an 'updated_at' column or similar, but simplified check:
# We rely on the state change from 1 (set in setup) to 0.

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "jdoe_exists": ${JDOE_EXISTS:-0},
    "jdoe_active": "${JDOE_ACTIVE:-1}",
    "admin_active": "${ADMIN_ACTIVE:-0}",
    "timestamp": "$(date -Iseconds)"
}
EOF

# 4. Move to final location (handle permissions)
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="