#!/bin/bash
echo "=== Setting up payroll_wage_audit_correction ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type preflight_check &>/dev/null; then
    preflight_check() {
        ensure_docker_containers
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi
if ! type ensure_docker_containers &>/dev/null; then
    ensure_docker_containers() {
        docker ps | grep -q timetrex || docker start timetrex timetrex-postgres 2>/dev/null || true
        sleep 3
    }
fi
if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "$1" 2>/dev/null | tr -d ' '
    }
fi

preflight_check

# Get the company_id from an existing employee
COMPANY_ID=$(timetrex_query "SELECT company_id FROM users WHERE deleted=0 AND status_id=10 LIMIT 1;" | head -1 | tr -d '[:space:]')
if [ -z "$COMPANY_ID" ]; then
    COMPANY_ID=1
fi

echo "Using company_id=$COMPANY_ID"

# Remove any stale test employees from a previous run
timetrex_query "UPDATE users SET deleted=1 WHERE employee_number IN ('EM-W001','EM-W002','EM-W003') AND deleted=0;" > /dev/null 2>&1

# Insert the three employees with WRONG wages (to be corrected by the agent)
# Victoria Chen — wrong wage $18.00 instead of $26.50
timetrex_query "
DO \$\$
DECLARE
  v_uid INTEGER;
BEGIN
  INSERT INTO users (company_id, status_id, employee_number, first_name, last_name, user_name, password, created_date, deleted)
  VALUES ($COMPANY_ID, 10, 'EM-W001', 'Victoria', 'Chen', 'victoria.chen.w001', md5('changeme'), extract(epoch from now())::integer, 0)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_uid;

  IF v_uid IS NULL THEN
    SELECT id INTO v_uid FROM users WHERE employee_number='EM-W001' AND deleted=0;
  END IF;

  DELETE FROM user_wage WHERE user_id=v_uid;
  INSERT INTO user_wage (user_id, type_id, wage, effective_date, created_date, deleted)
  VALUES (v_uid, 10, 18.00, '2026-01-01', extract(epoch from now())::integer, 0);
END;
\$\$;
" > /dev/null 2>&1

# Marcus Williams — wrong wage $24.00 instead of $32.00
timetrex_query "
DO \$\$
DECLARE
  v_uid INTEGER;
BEGIN
  INSERT INTO users (company_id, status_id, employee_number, first_name, last_name, user_name, password, created_date, deleted)
  VALUES ($COMPANY_ID, 10, 'EM-W002', 'Marcus', 'Williams', 'marcus.williams.w002', md5('changeme'), extract(epoch from now())::integer, 0)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_uid;

  IF v_uid IS NULL THEN
    SELECT id INTO v_uid FROM users WHERE employee_number='EM-W002' AND deleted=0;
  END IF;

  DELETE FROM user_wage WHERE user_id=v_uid;
  INSERT INTO user_wage (user_id, type_id, wage, effective_date, created_date, deleted)
  VALUES (v_uid, 10, 24.00, '2026-01-01', extract(epoch from now())::integer, 0);
END;
\$\$;
" > /dev/null 2>&1

# Patricia Nguyen — wrong wage $15.00 instead of $22.75
timetrex_query "
DO \$\$
DECLARE
  v_uid INTEGER;
BEGIN
  INSERT INTO users (company_id, status_id, employee_number, first_name, last_name, user_name, password, created_date, deleted)
  VALUES ($COMPANY_ID, 10, 'EM-W003', 'Patricia', 'Nguyen', 'patricia.nguyen.w003', md5('changeme'), extract(epoch from now())::integer, 0)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_uid;

  IF v_uid IS NULL THEN
    SELECT id INTO v_uid FROM users WHERE employee_number='EM-W003' AND deleted=0;
  END IF;

  DELETE FROM user_wage WHERE user_id=v_uid;
  INSERT INTO user_wage (user_id, type_id, wage, effective_date, created_date, deleted)
  VALUES (v_uid, 10, 15.00, '2026-01-01', extract(epoch from now())::integer, 0);
END;
\$\$;
" > /dev/null 2>&1

echo "Injected 3 employees with incorrect wages."

# Record start timestamp
date +%s > /tmp/payroll_wage_audit_correction_start_ts

# Ensure browser is open on TimeTrex
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|timetrex\|mozilla"; then
    su - ga -c "DISPLAY=:1 firefox http://localhost/interface/Login.php >> /home/ga/firefox.log 2>&1 &"
    sleep 8
fi

sleep 2
take_screenshot /tmp/payroll_wage_audit_correction_start_screenshot.png

echo "=== Setup Complete ==="
