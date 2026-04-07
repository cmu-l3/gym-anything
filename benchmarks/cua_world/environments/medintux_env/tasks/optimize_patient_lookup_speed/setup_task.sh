#!/bin/bash
set -e
echo "=== Setting up optimize_patient_lookup_speed task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
service mysql start 2>/dev/null || systemctl start mysql 2>/dev/null || true

# Wait for MySQL to be ready
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent; then
        break
    fi
    sleep 1
done

# Ensure database exists
if ! mysql -u root -e "USE DrTuxTest" 2>/dev/null; then
    echo "ERROR: DrTuxTest database not found. Re-initializing..."
    # Fallback: re-run setup scripts if needed, but assuming env is correct per spec
    # For now, just try to create it if missing (unlikely in this env)
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS DrTuxTest;"
fi

# REMOVE the index if it already exists (to ensure clean start state)
# Check for any index on FchPat_NumSS
echo "Cleaning up existing indexes on FchPat_NumSS..."
EXISTING_INDEXES=$(mysql -u root DrTuxTest -N -e "SELECT DISTINCT INDEX_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = 'DrTuxTest' AND TABLE_NAME = 'fchpat' AND COLUMN_NAME = 'FchPat_NumSS';")

for idx in $EXISTING_INDEXES; do
    echo "Dropping existing index: $idx"
    mysql -u root DrTuxTest -e "DROP INDEX $idx ON fchpat;"
done

# Verify clean state
COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = 'DrTuxTest' AND TABLE_NAME = 'fchpat' AND COLUMN_NAME = 'FchPat_NumSS';")
if [ "$COUNT" -eq 0 ]; then
    echo "Confirmed: No index exists on FchPat_NumSS."
else
    echo "WARNING: Failed to remove existing index."
fi

# Ensure output file doesn't exist
rm -f /home/ga/optimization_proof.txt

# Start a terminal for the user (since this is a DB task, they might want CLI)
if ! pgrep -f "xterm" > /dev/null; then
    su - ga -c "DISPLAY=:1 xterm -geometry 80x24 &"
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="