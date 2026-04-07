#!/bin/bash
echo "=== Exporting apac_regional_expansion result ==="

source /workspace/scripts/task_utils.sh

# Record end state
take_screenshot /tmp/task_end_screenshot.png

log "Querying database for all APAC expansion entities..."

# ---- 1. Business Unit ----
BU_ID=$(sentrifugo_db_query "SELECT id FROM main_businessunits WHERE unitname='Asia-Pacific Operations' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
BU_EXISTS="false"
if [ -n "$BU_ID" ]; then
    BU_EXISTS="true"
fi

# ---- 2. Departments (check BU linkage) ----
DEPT_PE_EXISTS="false"
DEPT_CS_EXISTS="false"
DEPT_PE_BU_MATCH="false"
DEPT_CS_BU_MATCH="false"

if [ -n "$BU_ID" ]; then
    DEPT_PE_ID=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptname='APAC Product Engineering' AND unitid=${BU_ID} AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
    DEPT_CS_ID=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptname='APAC Client Solutions' AND unitid=${BU_ID} AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$DEPT_PE_ID" ]; then DEPT_PE_EXISTS="true"; DEPT_PE_BU_MATCH="true"; fi
    if [ -n "$DEPT_CS_ID" ]; then DEPT_CS_EXISTS="true"; DEPT_CS_BU_MATCH="true"; fi
fi

# Also check if depts exist but under wrong BU
if [ "$DEPT_PE_EXISTS" = "false" ]; then
    DEPT_PE_ANY=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptname='APAC Product Engineering' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$DEPT_PE_ANY" ]; then DEPT_PE_EXISTS="true"; fi
fi
if [ "$DEPT_CS_EXISTS" = "false" ]; then
    DEPT_CS_ANY=$(sentrifugo_db_query "SELECT id FROM main_departments WHERE deptname='APAC Client Solutions' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$DEPT_CS_ANY" ]; then DEPT_CS_EXISTS="true"; fi
fi

# ---- 3. Job Titles ----
TITLE_RED=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='Regional Engineering Director' AND isactive=1;" | tr -d '[:space:]')
TITLE_CSA=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='Client Solutions Architect' AND isactive=1;" | tr -d '[:space:]')

# ---- 4. Employees ----
# Query each employee: check existence, department, and job title
get_employee_info() {
    local empid="$1"
    local uid=""
    # Try both EMP0XX and numeric-only patterns
    uid=$(sentrifugo_db_query "SELECT id FROM main_users WHERE (employeeId='${empid}' OR employeeId='${empid#EMP0}' OR employeeId='${empid#EMP}') AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
    if [ -z "$uid" ]; then
        # Try by first/last name as fallback
        echo "None"
        return
    fi

    # main_employees_summary has denormalized department_name and jobtitle_name
    local dept_name=$(sentrifugo_db_query "SELECT department_name FROM main_employees_summary WHERE user_id=${uid} LIMIT 1;" | tr -d '\n')
    if [ -z "$dept_name" ]; then
        # Fallback: try via department_id join
        dept_name=$(sentrifugo_db_query "SELECT d.deptname FROM main_employees_summary es LEFT JOIN main_departments d ON es.department_id=d.id WHERE es.user_id=${uid} LIMIT 1;" | tr -d '\n')
    fi

    local title_name=$(sentrifugo_db_query "SELECT jobtitle_name FROM main_employees_summary WHERE user_id=${uid} LIMIT 1;" | tr -d '\n')
    if [ -z "$title_name" ]; then
        # Fallback: try via jobtitle_id join
        title_name=$(sentrifugo_db_query "SELECT j.jobtitlename FROM main_employees_summary es LEFT JOIN main_jobtitles j ON es.jobtitle_id=j.id WHERE es.user_id=${uid} LIMIT 1;" | tr -d '\n')
    fi

    local firstname=$(sentrifugo_db_query "SELECT firstname FROM main_users WHERE id=${uid} LIMIT 1;" | tr -d '\n')
    local lastname=$(sentrifugo_db_query "SELECT lastname FROM main_users WHERE id=${uid} LIMIT 1;" | tr -d '\n')
    local email=$(sentrifugo_db_query "SELECT emailaddress FROM main_users WHERE id=${uid} LIMIT 1;" | tr -d '\n')

    python3 -c "
import json
print(json.dumps({
    'exists': True,
    'user_id': ${uid},
    'firstname': '''${firstname}''',
    'lastname': '''${lastname}''',
    'email': '''${email}''',
    'department': '''${dept_name}''',
    'jobtitle': '''${title_name}'''
}))
"
}

EMP025_JSON=$(get_employee_info "EMP025")
EMP026_JSON=$(get_employee_info "EMP026")
EMP027_JSON=$(get_employee_info "EMP027")

# Also try name-based lookup if empid lookup failed
if [ "$EMP025_JSON" = "None" ]; then
    WEI_UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Wei' AND lastname='Chen' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$WEI_UID" ]; then
        EMP025_JSON="{\"exists\": True, \"user_id\": ${WEI_UID}, \"firstname\": \"Wei\", \"lastname\": \"Chen\", \"found_by\": \"name\"}"
    fi
fi
if [ "$EMP026_JSON" = "None" ]; then
    PRIYA_UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Priya' AND lastname='Sharma' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$PRIYA_UID" ]; then
        EMP026_JSON="{\"exists\": True, \"user_id\": ${PRIYA_UID}, \"firstname\": \"Priya\", \"lastname\": \"Sharma\", \"found_by\": \"name\"}"
    fi
fi
if [ "$EMP027_JSON" = "None" ]; then
    KENJI_UID=$(sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='Kenji' AND lastname='Tanaka' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$KENJI_UID" ]; then
        EMP027_JSON="{\"exists\": True, \"user_id\": ${KENJI_UID}, \"firstname\": \"Kenji\", \"lastname\": \"Tanaka\", \"found_by\": \"name\"}"
    fi
fi

# ---- 5. Leave Type ----
LEAVE_EXISTS="false"
LEAVE_DAYS=""
LEAVE_ROW=$(sentrifugo_db_query "SELECT numberofdays FROM main_employeeleavetypes WHERE leavetype='Childcare Leave' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
if [ -n "$LEAVE_ROW" ]; then
    LEAVE_EXISTS="true"
    LEAVE_DAYS="$LEAVE_ROW"
fi

# ---- 6. Holiday Group and Dates ----
HG_ID=$(sentrifugo_db_query "SELECT id FROM main_holidaygroups WHERE groupname='Singapore Office Holidays 2026' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
HG_EXISTS="false"
HOLIDAYS_JSON="[]"
if [ -n "$HG_ID" ]; then
    HG_EXISTS="true"
    HOLIDAYS_RAW=$(sentrifugo_db_query "SELECT holidayname, holidaydate FROM main_holidaydates WHERE groupid=${HG_ID} AND isactive=1;")
    HOLIDAYS_JSON=$(python3 -c "
import sys, json
holidays = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split('\t')
    if len(parts) >= 2:
        holidays.append({'name': parts[0].strip(), 'date': parts[1].strip()})
print(json.dumps(holidays))
" <<< "$HOLIDAYS_RAW")
fi

# ---- 7. Time Module (tm_ prefixed tables) ----
CLIENT_ID=$(sentrifugo_db_query "SELECT id FROM tm_clients WHERE client_name='APAC Regional Program' AND is_active=1 LIMIT 1;" | tr -d '[:space:]')
CLIENT_EXISTS="false"
if [ -n "$CLIENT_ID" ]; then CLIENT_EXISTS="true"; fi

PROJ_ID=""
PROJ_EXISTS="false"
PROJ_CLIENT_MATCH="false"
if [ -n "$CLIENT_ID" ]; then
    PROJ_ID=$(sentrifugo_db_query "SELECT id FROM tm_projects WHERE project_name='Singapore Office Launch' AND client_id=${CLIENT_ID} AND is_active=1 LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$PROJ_ID" ]; then
        PROJ_EXISTS="true"
        PROJ_CLIENT_MATCH="true"
    fi
fi
# Check if project exists but with wrong client
if [ "$PROJ_EXISTS" = "false" ]; then
    PROJ_ID=$(sentrifugo_db_query "SELECT id FROM tm_projects WHERE project_name='Singapore Office Launch' AND is_active=1 LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$PROJ_ID" ]; then PROJ_EXISTS="true"; fi
fi

TASKS_JSON="[]"
RESOURCES_JSON="[]"
if [ -n "$PROJ_ID" ]; then
    # tm_project_tasks maps project_id -> task_id; tm_tasks has the task name in 'task' column
    TASKS_RAW=$(sentrifugo_db_query "SELECT t.task FROM tm_project_tasks pt JOIN tm_tasks t ON pt.task_id=t.id WHERE pt.project_id=${PROJ_ID} AND pt.is_active=1;")
    TASKS_JSON=$(python3 -c "import sys, json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))" <<< "$TASKS_RAW")

    # tm_project_employees maps project_id -> emp_id (which is main_users.id)
    RES_RAW=$(sentrifugo_db_query "SELECT u.employeeId FROM tm_project_employees pe JOIN main_users u ON pe.emp_id=u.id WHERE pe.project_id=${PROJ_ID} AND pe.is_active=1;")
    RESOURCES_JSON=$(python3 -c "import sys, json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))" <<< "$RES_RAW")
fi

# ---- 8. Announcement ----
ANNOUNCE_EXISTS="false"
ANNOUNCE_ID=$(sentrifugo_db_query "SELECT id FROM main_announcements WHERE title LIKE '%APAC Regional Expansion%' AND isactive=1 LIMIT 1;" | tr -d '[:space:]')
if [ -n "$ANNOUNCE_ID" ]; then ANNOUNCE_EXISTS="true"; fi

# ---- 9. Integrity check: verify existing employees unchanged ----
EMP001_DEPT=$(sentrifugo_db_query "SELECT department_name FROM main_employees_summary WHERE user_id=(SELECT id FROM main_users WHERE employeeId='EMP001' LIMIT 1) LIMIT 1;" | tr -d '\n')
EMP003_ACTIVE=$(sentrifugo_db_query "SELECT isactive FROM main_users WHERE employeeId='EMP003' LIMIT 1;" | tr -d '[:space:]')
EMP010_ACTIVE=$(sentrifugo_db_query "SELECT isactive FROM main_users WHERE employeeId='EMP010' LIMIT 1;" | tr -d '[:space:]')

# ---- Assemble result JSON ----
# Use Python to build JSON properly (bash true/false -> Python True/False)
RESULT_JSON=$(python3 << PYEOF
import json

def b(s):
    return s.lower() == 'true'

result = {
    'bu_exists': b('${BU_EXISTS}'),
    'dept_pe_exists': b('${DEPT_PE_EXISTS}'),
    'dept_pe_bu_match': b('${DEPT_PE_BU_MATCH}'),
    'dept_cs_exists': b('${DEPT_CS_EXISTS}'),
    'dept_cs_bu_match': b('${DEPT_CS_BU_MATCH}'),
    'title_red_exists': int('${TITLE_RED}' or '0') > 0,
    'title_csa_exists': int('${TITLE_CSA}' or '0') > 0,
    'emp025': ${EMP025_JSON},
    'emp026': ${EMP026_JSON},
    'emp027': ${EMP027_JSON},
    'leave_exists': b('${LEAVE_EXISTS}'),
    'leave_days': '${LEAVE_DAYS}' if '${LEAVE_DAYS}' else None,
    'holiday_group_exists': b('${HG_EXISTS}'),
    'holidays': ${HOLIDAYS_JSON},
    'client_exists': b('${CLIENT_EXISTS}'),
    'project_exists': b('${PROJ_EXISTS}'),
    'project_client_match': b('${PROJ_CLIENT_MATCH}'),
    'project_tasks': ${TASKS_JSON},
    'project_resources': ${RESOURCES_JSON},
    'announcement_exists': b('${ANNOUNCE_EXISTS}'),
    'integrity': {
        'emp001_dept': '${EMP001_DEPT}',
        'emp003_active': '${EMP003_ACTIVE}',
        'emp010_active': '${EMP010_ACTIVE}'
    },
    'export_timestamp': '$(date -Iseconds)'
}

print(json.dumps(result, indent=2, default=str))
PYEOF
)

safe_write_result "$RESULT_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="
