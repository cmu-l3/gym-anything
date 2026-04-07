#!/bin/bash
# Setup script for Workforce Planning Staging Pipeline task
echo "=== Setting up Workforce Planning Staging Pipeline ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# Verify HR schema exists
HR_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM hr.employees;" "system" | tr -d '[:space:]')
if [ -z "$HR_CHECK" ] || [ "$HR_CHECK" = "ERROR" ] || [ "$HR_CHECK" -lt 1 ] 2>/dev/null; then
    echo "ERROR: HR schema not loaded or inaccessible"
    exit 1
fi
echo "HR schema verified ($HR_CHECK employees)"

# Clean up any existing artifacts from previous attempts
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP VIEW hr.workforce_summary_vw';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE hr.workforce_staging CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

# Ensure export directory exists and clean old CSVs
mkdir -p /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/workforce_staging.csv
chown -R ga:ga /home/ga/Documents/exports

# Setup SQL Developer Connection for agent
ensure_hr_connection "HR Database" "hr" "hr123"

# Open SQL Developer to the connection
if is_sqldeveloper_running; then
    open_hr_connection_in_sqldeveloper
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png ga
echo "Initial state recorded."

echo "=== Setup complete ==="