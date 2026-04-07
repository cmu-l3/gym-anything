#!/bin/bash
echo "=== Setting up REST API Patient Lookup Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for PostgreSQL to be ready
echo "Waiting for database..."
for i in {1..30}; do
    if docker exec nextgen-postgres pg_isready -U postgres >/dev/null 2>&1; then
        echo "Database ready."
        break
    fi
    sleep 1
done

# Create and populate the hospital_patients table
echo "Populating database..."
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
DROP TABLE IF EXISTS hospital_patients;
CREATE TABLE hospital_patients (
    mrn TEXT PRIMARY KEY,
    full_name TEXT NOT NULL,
    status TEXT NOT NULL,
    last_visit DATE DEFAULT CURRENT_DATE
);

INSERT INTO hospital_patients (mrn, full_name, status) VALUES
('MRN-1001', 'John Doe', 'Active'),
('MRN-1002', 'Jane Smith', 'Discharged'),
('MRN-1003', 'Robert Johnson', 'Admitted'),
('MRN-1004', 'Emily Davis', 'Pre-Admit'),
('MRN-1005', 'Michael Brown', 'Deceased');
"

# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - REST API Gateway Task"
echo "============================================"
echo ""
echo "TASK: Create an HTTP API on port 6670"
echo ""
echo "Database Connection Info:"
echo "  URL: jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "  User: postgres"
echo "  Pass: postgres"
echo "  Table: hospital_patients (columns: mrn, full_name, status)"
echo ""
echo "Test Data:"
echo "  MRN-1001 -> John Doe"
echo "  MRN-1002 -> Jane Smith"
echo ""
echo "Tools:"
echo "  - Administrator Dashboard (Firefox)"
echo "  - curl (for testing APIs)"
echo "  - psql (for checking DB)"
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
# Focus the terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Maximize Firefox if open
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="