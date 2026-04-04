#!/bin/bash
set -u

echo "=== Setting up Optimize Scheduler Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Ensure OpenMRS/Bahmni is running
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni/OpenMRS did not become ready in time."
    exit 1
fi

# 3. Setup the Scheduler Task in the Database
# We use docker exec to run SQL directly against the openmrs database
# We ensure the task exists with 'repeat_interval' = 5

echo "Configuring initial scheduler task state..."

TASK_NAME="HL7 Inbound Queue Processor"
TASK_CLASS="org.openmrs.module.hl7.HL7InboundQueueProcessorTask"
INITIAL_INTERVAL=5
TASK_UUID="d2c206d0-621f-11e5-a837-0800200c9a66" # Fixed UUID for tracking

# SQL to insert or update the task
# We use ON DUPLICATE KEY UPDATE logic or just DELETE/INSERT to ensure clean state
SETUP_SQL="
USE openmrs;
DELETE FROM scheduler_task_config WHERE name = '${TASK_NAME}';
INSERT INTO scheduler_task_config (
    name, 
    description, 
    schedulable_class, 
    start_time, 
    start_on_startup, 
    repeat_interval, 
    date_created, 
    created_by, 
    uuid
) VALUES (
    '${TASK_NAME}',
    'Processes inbound HL7 queue',
    '${TASK_CLASS}',
    NOW(),
    1,
    ${INITIAL_INTERVAL},
    NOW(),
    1,
    '${TASK_UUID}'
);
"

# Execute SQL inside the database container
docker exec -i bahmni-openmrsdb mysql -u openmrs-user -ppassword < <(echo "$SETUP_SQL") 2>/dev/null

if [ $? -eq 0 ]; then
    echo "Scheduler task '${TASK_NAME}' reset to interval ${INITIAL_INTERVAL}."
else
    echo "ERROR: Failed to setup scheduler task in database."
    exit 1
fi

# 4. Launch Browser to OpenMRS Admin Page
# The task requires navigating the legacy admin UI, not the React clinical app
OPENMRS_ADMIN_URL="https://localhost/openmrs/admin"

echo "Starting browser at ${OPENMRS_ADMIN_URL}..."
start_browser "$OPENMRS_ADMIN_URL"

# 5. Capture Initial State Screenshot
sleep 2
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task Setup Complete ==="