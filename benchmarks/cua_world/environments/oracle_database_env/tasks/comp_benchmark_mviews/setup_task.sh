#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up comp_benchmark_mviews task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Oracle is running
echo "Checking Oracle status..."
if ! sudo docker ps | grep -q oracle-xe; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

# Clean up any pre-existing objects to ensure a fresh start
echo "Cleaning up existing objects..."
oracle_query "
BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW MV_DEPT_COMP_SUMMARY';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW MV_JOB_SALARY_BANDS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW MV_HIRE_DECADE_STATS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP PROCEDURE REFRESH_COMP_VIEWS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
" "hr" > /dev/null 2>&1 || true

# Grant necessary privileges to HR user
# CREATE MATERIALIZED VIEW and QUERY REWRITE are required
echo "Granting privileges..."
oracle_query "
GRANT CREATE MATERIALIZED VIEW TO hr;
GRANT QUERY REWRITE TO hr;
" "system" > /dev/null 2>&1 || true

# Remove any old export file
rm -f /home/ga/Desktop/compensation_benchmark.txt

# Record baseline MV count (should be 0)
MV_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_mviews;" "hr" | tr -d ' ')
echo "$MV_COUNT" > /tmp/initial_mv_count.txt

# Open terminal for the agent
if ! pgrep -f "xfce4-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 xfce4-terminal --maximize &" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="