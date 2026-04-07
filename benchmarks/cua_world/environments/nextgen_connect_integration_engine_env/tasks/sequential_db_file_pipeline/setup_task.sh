#!/bin/bash
echo "=== Setting up Sequential Pipeline Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Output Directory
echo "Preparing output directory..."
mkdir -p /tmp/billing_out
chmod 777 /tmp/billing_out
# Clean any existing files to ensure clean state
rm -f /tmp/billing_out/*

# 2. Prepare Database Table (with Primary Key for constraint testing)
echo "Setting up PostgreSQL table..."
# Wait for Postgres
for i in {1..30}; do
    if docker exec nextgen-postgres pg_isready -U postgres >/dev/null 2>&1; then
        break
    fi
    echo "Waiting for PostgreSQL..."
    sleep 1
done

# Create table with PRIMARY KEY on visit_number
# This is critical: inserting the same visit_number twice must throw an error
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
    DROP TABLE IF EXISTS billing_log;
    CREATE TABLE billing_log (
        visit_number VARCHAR(50) PRIMARY KEY,
        patient_name VARCHAR(100),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    GRANT ALL PRIVILEGES ON TABLE billing_log TO postgres;
"

# 3. Open Terminal for User
echo "Launching terminal..."
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - Transactional Pipeline"
echo "============================================"
echo ""
echo "TASK: Create channel \"Registration_Pipeline\""
echo "  1. Source: TCP Listener on Port 6665"
echo "  2. Dest 1: Database Writer -> table \"billing_log\""
echo "     - Map PV1.19 -> visit_number (Primary Key)"
echo "     - Map PID.5  -> patient_name"
echo "  3. Dest 2: File Writer -> /tmp/billing_out/"
echo ""
echo "CRITICAL REQUIREMENT:"
echo "  Configure Destination 2 to WAIT for Destination 1."
echo "  If Dest 1 fails (duplicate key), Dest 2 must NOT run."
echo ""
echo "Database: jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "Creds: postgres / postgres"
echo ""
echo "Tools: curl, nc, python3"
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="