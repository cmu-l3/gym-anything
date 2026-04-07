#!/bin/bash
# Setup script for PL/SQL Debugging Challenge
# Installs buggy PL/SQL objects and prepares test data

set -e

echo "=== Setting up PL/SQL Debug Challenge ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# --- 1. Verify Database Connection ---
echo "Verifying Oracle connectivity..."
if ! wait_for_oracle_ready; then
    echo "ERROR: Oracle database not ready"
    exit 1
fi

# --- 2. Clean up Previous State ---
echo "Cleaning up previous objects..."
oracle_query "
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE dept_salary_rankings';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DELETE FROM employees WHERE employee_id = 250';
    COMMIT;
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

# --- 3. Create Support Structures ---
echo "Creating support tables and test data..."
# Create table for ranking procedure
oracle_query "
CREATE TABLE dept_salary_rankings (
    employee_id NUMBER,
    department_id NUMBER,
    salary NUMBER,
    dept_rank NUMBER
);
" "hr" > /dev/null 2>&1

# Insert test employee for ADJUST_SALARY (ID 250)
# Valid salary 5000. 10% raise should be 5500. Bug will make it 5010.
oracle_query "
INSERT INTO employees (employee_id, first_name, last_name, email, phone_number, hire_date, job_id, salary, commission_pct, manager_id, department_id)
VALUES (250, 'Test', 'Debugger', 'TDEBUG', '555.0250', SYSDATE, 'IT_PROG', 5000, NULL, 103, 60);
COMMIT;
" "hr" > /dev/null 2>&1

# --- 4. Install Buggy PL/SQL Objects ---
echo "Installing buggy PL/SQL objects..."

# Bug 1: CALC_ANNUAL_COMPENSATION (NULL commission bug)
oracle_query "
CREATE OR REPLACE FUNCTION calc_annual_compensation(p_emp_id NUMBER) RETURN NUMBER IS
    l_salary    NUMBER;
    l_commission NUMBER;
BEGIN
    SELECT salary, commission_pct
    INTO l_salary, l_commission
    FROM employees
    WHERE employee_id = p_emp_id;
    
    -- BUG: l_commission is NULL for most employees, making result NULL
    -- Should be NVL(l_commission, 0)
    RETURN l_salary * 12 * (1 + l_commission);
END;
/
" "hr" > /dev/null 2>&1

# Bug 2: BUILD_DEPT_SALARY_RANKINGS (Wrong sort order)
oracle_query "
CREATE OR REPLACE PROCEDURE build_dept_salary_rankings IS
BEGIN
    EXECUTE IMMEDIATE 'TRUNCATE TABLE dept_salary_rankings';
    
    INSERT INTO dept_salary_rankings (employee_id, department_id, salary, dept_rank)
    SELECT employee_id, department_id, salary,
           -- BUG: ORDER BY salary ASC gives rank 1 to LOWEST salary
           -- Should be DESC
           RANK() OVER (PARTITION BY department_id ORDER BY salary ASC)
    FROM employees
    WHERE department_id IS NOT NULL;
    
    COMMIT;
END;
/
" "hr" > /dev/null 2>&1

# Bug 3: FIND_DEPT_TOP_EARNER (MIN instead of MAX)
oracle_query "
CREATE OR REPLACE FUNCTION find_dept_top_earner(p_dept_id NUMBER) RETURN NUMBER IS
    l_emp_id NUMBER;
BEGIN
    SELECT employee_id INTO l_emp_id
    FROM employees
    WHERE department_id = p_dept_id
      -- BUG: MIN instead of MAX
      AND salary = (SELECT MIN(salary) FROM employees WHERE department_id = p_dept_id)
      AND ROWNUM = 1;
    
    RETURN l_emp_id;
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/
" "hr" > /dev/null 2>&1

# Bug 4: GET_SALARY_PERCENTILE (Missing partition/dept filter in analytics)
oracle_query "
CREATE OR REPLACE FUNCTION get_salary_percentile(p_emp_id NUMBER) RETURN NUMBER IS
    l_percentile NUMBER;
    l_dept_id    NUMBER;
BEGIN
    SELECT department_id INTO l_dept_id FROM employees WHERE employee_id = p_emp_id;
    
    -- BUG: Computes percentile across ALL employees, ignoring department context
    -- Should be PARTITION BY department_id or WHERE department_id = l_dept_id
    SELECT ROUND(pct * 100) INTO l_percentile
    FROM (
        SELECT employee_id,
               PERCENT_RANK() OVER (ORDER BY salary) AS pct
        FROM employees
    )
    WHERE employee_id = p_emp_id;
    
    RETURN l_percentile;
END;
/
" "hr" > /dev/null 2>&1

# Bug 5: ADJUST_SALARY (Raw number add instead of percentage)
oracle_query "
CREATE OR REPLACE PROCEDURE adjust_salary(p_emp_id NUMBER, p_pct_increase NUMBER) IS
BEGIN
    -- BUG: Adds the raw number instead of computing percentage
    -- e.g., 10% increase on 4400 becomes 4410 instead of 4840
    UPDATE employees
    SET salary = salary + p_pct_increase
    WHERE employee_id = p_emp_id;
    
    COMMIT;
END;
/
" "hr" > /dev/null 2>&1

# --- 5. Create Source Code Reference File ---
echo "Creating buggy source code file on Desktop..."
cat > /home/ga/Desktop/buggy_source.sql << 'EOF'
--------------------------------------------------------------------------------
-- BUGGY PL/SQL SOURCE CODE
-- TASK: Fix the logic errors in these 5 objects.
--------------------------------------------------------------------------------

-- OBJECT 1: CALC_ANNUAL_COMPENSATION
-- Goal: Return (salary * 12 * (1 + commission_pct)). Treat NULL commission as 0.
CREATE OR REPLACE FUNCTION calc_annual_compensation(p_emp_id NUMBER) RETURN NUMBER IS
    l_salary    NUMBER;
    l_commission NUMBER;
BEGIN
    SELECT salary, commission_pct
    INTO l_salary, l_commission
    FROM employees
    WHERE employee_id = p_emp_id;
    
    RETURN l_salary * 12 * (1 + l_commission);
END;
/

-- OBJECT 2: BUILD_DEPT_SALARY_RANKINGS
-- Goal: Populate table with Rank 1 = HIGHEST salary in department.
CREATE OR REPLACE PROCEDURE build_dept_salary_rankings IS
BEGIN
    EXECUTE IMMEDIATE 'TRUNCATE TABLE dept_salary_rankings';
    
    INSERT INTO dept_salary_rankings (employee_id, department_id, salary, dept_rank)
    SELECT employee_id, department_id, salary,
           RANK() OVER (PARTITION BY department_id ORDER BY salary ASC)
    FROM employees
    WHERE department_id IS NOT NULL;
    
    COMMIT;
END;
/

-- OBJECT 3: FIND_DEPT_TOP_EARNER
-- Goal: Return the employee_id of the person with the HIGHEST salary in dept.
CREATE OR REPLACE FUNCTION find_dept_top_earner(p_dept_id NUMBER) RETURN NUMBER IS
    l_emp_id NUMBER;
BEGIN
    SELECT employee_id INTO l_emp_id
    FROM employees
    WHERE department_id = p_dept_id
      AND salary = (SELECT MIN(salary) FROM employees WHERE department_id = p_dept_id)
      AND ROWNUM = 1;
    
    RETURN l_emp_id;
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN NULL;
END;
/

-- OBJECT 4: GET_SALARY_PERCENTILE
-- Goal: Return percentile (0-100) of employee's salary WITHIN THEIR OWN DEPARTMENT.
CREATE OR REPLACE FUNCTION get_salary_percentile(p_emp_id NUMBER) RETURN NUMBER IS
    l_percentile NUMBER;
    l_dept_id    NUMBER;
BEGIN
    SELECT department_id INTO l_dept_id FROM employees WHERE employee_id = p_emp_id;
    
    SELECT ROUND(pct * 100) INTO l_percentile
    FROM (
        SELECT employee_id,
               PERCENT_RANK() OVER (ORDER BY salary) AS pct
        FROM employees
    )
    WHERE employee_id = p_emp_id;
    
    RETURN l_percentile;
END;
/

-- OBJECT 5: ADJUST_SALARY
-- Goal: Increase salary by percentage (e.g. 10 = +10%).
CREATE OR REPLACE PROCEDURE adjust_salary(p_emp_id NUMBER, p_pct_increase NUMBER) IS
BEGIN
    UPDATE employees
    SET salary = salary + p_pct_increase
    WHERE employee_id = p_emp_id;
    
    COMMIT;
END;
/
EOF
chown ga:ga /home/ga/Desktop/buggy_source.sql

# --- 6. Initial Verification ---
# Populate rankings table initially (with buggy data)
oracle_query "BEGIN build_dept_salary_rankings; END;" "hr" > /dev/null 2>&1

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="