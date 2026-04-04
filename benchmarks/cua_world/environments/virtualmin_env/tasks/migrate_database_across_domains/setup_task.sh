#!/bin/bash
echo "=== Setting up migrate_database_across_domains task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type virtualmin_db_query &>/dev/null; then
    echo "WARNING: task_utils.sh functions not available, using inline definitions"
    virtualmin_db_query() { mysql -u root -pGymAnything123! -N -e "$1" 2>/dev/null || true; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
    ensure_virtualmin_ready() { true; }
    navigate_to() {
        DISPLAY=:1 xdotool key ctrl+l; sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "$1"; sleep 0.3
        DISPLAY=:1 xdotool key Return; sleep 4
    }
fi

TARGET_DOMAIN="brightstar.test"

# Verify domain exists
if ! virtualmin list-domains --name-only 2>/dev/null | grep -q "^${TARGET_DOMAIN}$"; then
    echo "ERROR: ${TARGET_DOMAIN} does not exist!"
    exit 1
fi

# Verify sakila database exists
SAKILA_EXISTS=$(virtualmin_db_query "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='sakila';")
echo "Sakila database exists: ${SAKILA_EXISTS}"
if [ "${SAKILA_EXISTS:-0}" -eq 0 ]; then
    echo "WARNING: Sakila database does not exist — some subtasks may not be verifiable"
fi

# Clean up any previous run artifacts
echo "--- Cleaning up previous run artifacts ---"
# Drop brightstar_catalog or brightstar_brightstar_catalog if they exist
for dbname in brightstar_catalog brightstar_brightstar_catalog; do
    virtualmin_db_query "DROP DATABASE IF EXISTS \`${dbname}\`;" 2>/dev/null || true
done

# Revoke brightstar access to sakila (if previously granted, on any host)
for host in localhost 10.0.2.15 virtualmin.gym-anything.local '%'; do
    virtualmin_db_query "REVOKE ALL PRIVILEGES ON sakila.* FROM 'brightstar'@'${host}';" 2>/dev/null || true
done
virtualmin_db_query "FLUSH PRIVILEGES;" 2>/dev/null || true

sleep 2

# Record baseline state
echo "--- Recording baseline state ---"
INITIAL_DBS=$(virtualmin_db_query "SHOW DATABASES;")
INITIAL_DB_COUNT=$(echo "$INITIAL_DBS" | wc -l)

# Check if brightstar user can access sakila (try any host)
SAKILA_ACCESS="NONE"
for host in localhost 10.0.2.15 virtualmin.gym-anything.local '%'; do
    GRANT_CHECK=$(virtualmin_db_query "SHOW GRANTS FOR 'brightstar'@'${host}';" 2>/dev/null | grep -i sakila || echo "")
    if [ -n "$GRANT_CHECK" ]; then
        SAKILA_ACCESS="$GRANT_CHECK"
        break
    fi
done

cat > /tmp/initial_db_state.json << EOF
{
    "domain": "${TARGET_DOMAIN}",
    "initial_db_count": ${INITIAL_DB_COUNT:-0},
    "sakila_exists": ${SAKILA_EXISTS:-0},
    "initial_sakila_access": "$(echo "$SAKILA_ACCESS" | head -1)"
}
EOF

cat /tmp/initial_db_state.json

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is ready
ensure_virtualmin_ready
sleep 2

# Navigate to Virtualmin dashboard
navigate_to "https://localhost:10000/virtual-server/index.cgi"
sleep 3

take_screenshot /tmp/task_start_screenshot.png
echo "=== migrate_database_across_domains task setup complete ==="
