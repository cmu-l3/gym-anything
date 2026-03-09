#!/bin/bash
echo "=== Setting up setup_scheduled_backup task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type virtualmin_list_domains &>/dev/null; then
    echo "WARNING: task_utils.sh functions not available, using inline definitions"
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
    ensure_virtualmin_ready() { true; }
    navigate_to() {
        DISPLAY=:1 xdotool key ctrl+l; sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "$1"; sleep 0.3
        DISPLAY=:1 xdotool key Return; sleep 4
    }
fi

# Verify all 3 domains exist
for domain in acmecorp.test brightstar.test greenvalley.test; do
    if ! virtualmin list-domains --name-only 2>/dev/null | grep -q "^${domain}$"; then
        echo "ERROR: ${domain} does not exist!"
        exit 1
    fi
done

# Clean up: delete any existing scheduled backups
echo "--- Removing existing scheduled backups ---"
EXISTING_BACKUPS=$(virtualmin list-scheduled-backups --multiline 2>/dev/null)
if [ -n "$EXISTING_BACKUPS" ]; then
    # Extract backup IDs and delete them
    echo "$EXISTING_BACKUPS" | grep -i "^[[:space:]]*id:" | awk '{print $NF}' | while read bid; do
        if [ -n "$bid" ]; then
            virtualmin delete-scheduled-backup --id "$bid" 2>/dev/null || true
        fi
    done
fi
# Also try deleting by index
for i in $(seq 0 10); do
    virtualmin delete-scheduled-backup --id "$i" 2>/dev/null || true
done

# Remove backup directory if it exists (agent needs to create it)
rm -rf /backup/virtualmin 2>/dev/null || true

# Record baseline state
echo "--- Recording baseline state ---"
INITIAL_SCHEDULED_COUNT=$(virtualmin list-scheduled-backups 2>/dev/null | grep -c "Destination" || echo "0")

cat > /tmp/initial_backup_state.json << EOF
{
    "initial_scheduled_backup_count": ${INITIAL_SCHEDULED_COUNT:-0},
    "backup_dir_exists": false
}
EOF

cat /tmp/initial_backup_state.json

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is ready
ensure_virtualmin_ready
sleep 2

# Navigate to Virtualmin dashboard
navigate_to "https://localhost:10000/virtual-server/index.cgi"
sleep 3

take_screenshot /tmp/task_start_screenshot.png
echo "=== setup_scheduled_backup task setup complete ==="
