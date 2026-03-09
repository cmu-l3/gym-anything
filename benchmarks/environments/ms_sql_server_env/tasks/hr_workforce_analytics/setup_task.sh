#!/bin/bash
# Setup for hr_workforce_analytics task
echo "=== Setting up hr_workforce_analytics task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# Clean up any previous task artifacts
# ============================================================
echo "Cleaning up previous task artifacts..."

# Drop stored procedure
mssql_query "
IF OBJECT_ID('HumanResources.usp_RefreshWorkforceSummary', 'P') IS NOT NULL
    DROP PROCEDURE HumanResources.usp_RefreshWorkforceSummary
" "AdventureWorks2022"

# Drop summary table (and its index)
mssql_query "
IF OBJECT_ID('HumanResources.WorkforceSummary', 'U') IS NOT NULL
    DROP TABLE HumanResources.WorkforceSummary
" "AdventureWorks2022"

echo "Cleanup complete."

# ============================================================
# Record initial state / baselines
# ============================================================
echo "Recording initial state..."

DEPT_COUNT=$(mssql_query "SELECT COUNT(*) FROM HumanResources.Department" "AdventureWorks2022" | tr -d ' \r\n')
EMPLOYEE_COUNT=$(mssql_query "SELECT COUNT(*) FROM HumanResources.Employee" "AdventureWorks2022" | tr -d ' \r\n')
ACTIVE_DEPT_HIST=$(mssql_query "SELECT COUNT(DISTINCT DepartmentID) FROM HumanResources.EmployeeDepartmentHistory WHERE EndDate IS NULL" "AdventureWorks2022" | tr -d ' \r\n')
PAY_HISTORY_COUNT=$(mssql_query "SELECT COUNT(*) FROM HumanResources.EmployeePayHistory" "AdventureWorks2022" | tr -d ' \r\n')

echo "Departments: $DEPT_COUNT" > /tmp/initial_state.txt
echo "Employees: $EMPLOYEE_COUNT" >> /tmp/initial_state.txt
echo "Active departments with employees: $ACTIVE_DEPT_HIST" >> /tmp/initial_state.txt
echo "Pay history records: $PAY_HISTORY_COUNT" >> /tmp/initial_state.txt
echo "Setup timestamp: $(date -Iseconds)" >> /tmp/initial_state.txt

cat /tmp/initial_state.txt

# ============================================================
# Ensure Azure Data Studio is running and connected
# ============================================================
echo "Ensuring Azure Data Studio is running and connected..."

ADS_RUNNING=false
if pgrep -f "azuredatastudio" > /dev/null 2>&1; then
    ADS_RUNNING=true
    echo "Azure Data Studio is already running"
fi

if [ "$ADS_RUNNING" = false ]; then
    echo "Launching Azure Data Studio..."
    ADS_CMD="/snap/bin/azuredatastudio"
    if [ ! -x "$ADS_CMD" ]; then
        ADS_CMD="azuredatastudio"
    fi
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/azuredatastudio_task.log 2>&1 &"

    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "azure\|data studio"; then
            echo "ADS window detected after ${i}s"
            break
        fi
        sleep 1
    done
fi

sleep 5

WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2

DISPLAY=:1 xdotool key Tab Tab Return
sleep 1
DISPLAY=:1 xdotool mousemove 1879 1015 click 1
sleep 1
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 0.5

echo "Establishing SQL Server connection..."
DISPLAY=:1 xdotool key F1
sleep 1
DISPLAY=:1 xdotool type 'new connection'
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

DISPLAY=:1 xdotool mousemove 1740 690 click 1
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a
DISPLAY=:1 xdotool type 'localhost'
sleep 0.3

DISPLAY=:1 xdotool mousemove 1740 755 click 1
sleep 0.3
DISPLAY=:1 xdotool type 'sa'
sleep 0.3

DISPLAY=:1 xdotool mousemove 1740 785 click 1
sleep 0.3
DISPLAY=:1 xdotool type 'GymAnything#2024'
sleep 0.3

DISPLAY=:1 xdotool mousemove 1740 905 click 1
sleep 0.5
DISPLAY=:1 xdotool key t Return
sleep 0.5

DISPLAY=:1 xdotool mousemove 1770 1049 click 1
sleep 5

CONNECTION_ESTABLISHED=false
for i in $(seq 1 15); do
    TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure" | head -1)
    if echo "$TITLE" | grep -qi "localhost.*Azure"; then
        CONNECTION_ESTABLISHED=true
        echo "Connection established after ${i}s"
        break
    fi
    if [ "$i" -eq 8 ]; then DISPLAY=:1 xdotool key Return; fi
    sleep 1
done

if [ "$CONNECTION_ESTABLISHED" = "false" ]; then
    echo "Retrying connection..."
    DISPLAY=:1 xdotool key Escape; sleep 0.5
    DISPLAY=:1 xdotool key F1; sleep 1
    DISPLAY=:1 xdotool type 'new connection'; sleep 1
    DISPLAY=:1 xdotool key Return; sleep 2
    DISPLAY=:1 xdotool mousemove 1740 690 click 1; sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a; DISPLAY=:1 xdotool type 'localhost'; sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 755 click 1; sleep 0.3
    DISPLAY=:1 xdotool type 'sa'; sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 785 click 1; sleep 0.3
    DISPLAY=:1 xdotool type 'GymAnything#2024'; sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 905 click 1; sleep 0.5
    DISPLAY=:1 xdotool key t Return; sleep 0.5
    DISPLAY=:1 xdotool mousemove 1770 1049 click 1; sleep 8
fi

# Open new query editor
DISPLAY=:1 xdotool key F1
sleep 0.5
DISPLAY=:1 xdotool type 'new query'
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 2

DISPLAY=:1 xdotool mousemove 600 400 click 1
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a Delete
sleep 0.5

DISPLAY=:1 xdotool mousemove 1889 917 click 1
sleep 0.5
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool mousemove 960 400 click 1
sleep 0.5

DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo ""
echo "Azure Data Studio is running and connected to SQL Server."
echo ""
echo "Task: HR Workforce Analytics"
echo "1. Create table 'HumanResources.WorkforceSummary' with 13 columns"
echo "2. Create stored procedure 'HumanResources.usp_RefreshWorkforceSummary'"
echo "   - Uses ROW_NUMBER() to get most recent pay rate per employee"
echo "   - Joins: Department, EmployeeDepartmentHistory, Employee, EmployeePayHistory"
echo "   - Conditional aggregation for gender counts"
echo "   - DATEDIFF for tenure calculation"
echo "3. Execute: EXEC HumanResources.usp_RefreshWorkforceSummary"
echo "4. Create non-clustered index on HumanResources.WorkforceSummary(DepartmentID)"
echo ""
exit 0
