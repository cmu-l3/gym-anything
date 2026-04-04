#!/bin/bash
# Export result for "service_catalog_department_setup" task

echo "=== Exporting Service Catalog Department Setup Result ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

RESULT_FILE="/tmp/service_catalog_department_setup_result.json"

take_screenshot "/tmp/service_catalog_department_setup_final.png" 2>/dev/null || true

# --- SQL queries for department, category, subcategory, group, template ---
# Department
DEPT_RESEARCH=$(sdp_db_exec "SELECT COUNT(*) FROM department WHERE LOWER(name) LIKE '%research computing%';" 2>/dev/null | tr -d '[:space:]')
DEPT_RESEARCH_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM sdorg WHERE LOWER(name) LIKE '%research computing%';" 2>/dev/null | tr -d '[:space:]')

# Category
CAT_RESEARCH=$(sdp_db_exec "SELECT COUNT(*) FROM category WHERE LOWER(name) LIKE '%research computing%';" 2>/dev/null | tr -d '[:space:]')
CAT_RESEARCH_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM categorydefn WHERE LOWER(name) LIKE '%research computing%';" 2>/dev/null | tr -d '[:space:]')
CAT_ID=$(sdp_db_exec "SELECT categoryid FROM category WHERE LOWER(name) LIKE '%research computing%' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
CAT_ID_ALT=$(sdp_db_exec "SELECT id FROM categorydefn WHERE LOWER(name) LIKE '%research computing%' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# Subcategories
SUBCAT_HPC=$(sdp_db_exec "SELECT COUNT(*) FROM subcategory WHERE LOWER(name) LIKE '%hpc%' OR LOWER(name) LIKE '%cluster%';" 2>/dev/null | tr -d '[:space:]')
SUBCAT_STORAGE=$(sdp_db_exec "SELECT COUNT(*) FROM subcategory WHERE LOWER(name) LIKE '%research data%' OR LOWER(name) LIKE '%data storage%';" 2>/dev/null | tr -d '[:space:]')
SUBCAT_SOFTWARE=$(sdp_db_exec "SELECT COUNT(*) FROM subcategory WHERE LOWER(name) LIKE '%scientific%' OR (LOWER(name) LIKE '%software%' AND LOWER(name) NOT LIKE '%application%');" 2>/dev/null | tr -d '[:space:]')

# Technician Group
GRP_RESEARCH=$(sdp_db_exec "SELECT COUNT(*) FROM supportgroup WHERE LOWER(groupname) LIKE '%research computing%';" 2>/dev/null | tr -d '[:space:]')

# Request Template
TMPL_HPC=$(sdp_db_exec "SELECT COUNT(*) FROM workordertemplate WHERE LOWER(name) LIKE '%hpc%' OR LOWER(name) LIKE '%cluster access%';" 2>/dev/null | tr -d '[:space:]')
TMPL_HPC_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM requesttemplate WHERE LOWER(name) LIKE '%hpc%' OR LOWER(name) LIKE '%cluster access%';" 2>/dev/null | tr -d '[:space:]')

cat > /tmp/service_catalog_sql_raw.json << SQLEOF
{
  "dept_research_computing_sql": ${DEPT_RESEARCH:-0},
  "dept_research_computing_alt_sql": ${DEPT_RESEARCH_ALT:-0},
  "cat_research_computing_sql": ${CAT_RESEARCH:-0},
  "cat_research_computing_alt_sql": ${CAT_RESEARCH_ALT:-0},
  "cat_id_sql": "${CAT_ID:-}",
  "cat_id_alt_sql": "${CAT_ID_ALT:-}",
  "subcat_hpc_sql": ${SUBCAT_HPC:-0},
  "subcat_storage_sql": ${SUBCAT_STORAGE:-0},
  "subcat_software_sql": ${SUBCAT_SOFTWARE:-0},
  "group_research_sql": ${GRP_RESEARCH:-0},
  "template_hpc_sql": ${TMPL_HPC:-0},
  "template_hpc_alt_sql": ${TMPL_HPC_ALT:-0}
}
SQLEOF

# --- Python: REST API queries ---
python3 << 'PYEOF'
import json, ssl, urllib.request, urllib.parse, os

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

API_KEY = open('/tmp/sdp_api_key.txt').read().strip() if os.path.exists('/tmp/sdp_api_key.txt') else ''
BASE = 'https://localhost:8080'

def api_get(path, params=None):
    url = f'{BASE}{path}'
    if params:
        url += '?input_data=' + urllib.parse.quote(json.dumps(params))
    req = urllib.request.Request(url, headers={'authtoken': API_KEY})
    try:
        resp = urllib.request.urlopen(req, context=ctx, timeout=30)
        return json.loads(resp.read())
    except Exception as e:
        return {'_error': str(e)}

with open('/tmp/service_catalog_sql_raw.json') as f:
    result = json.load(f)

# API checks for categories
cats_resp = api_get('/api/v3/categories', {'list_info': {'row_count': 100}})
categories = cats_resp.get('categories', [])
research_cat_found_api = any('research computing' in (c.get('name', '') or '').lower() for c in categories)
result['cat_research_computing_api'] = research_cat_found_api

# API checks for subcategories
subcats_resp = api_get('/api/v3/subcategories', {'list_info': {'row_count': 200}})
subcategories = subcats_resp.get('subcategories', [])
subcat_names = [s.get('name', '').lower() for s in subcategories]
hpc_found_api = any('hpc' in n or 'cluster' in n for n in subcat_names)
storage_found_api = any('research data' in n or 'data storage' in n for n in subcat_names)
software_found_api = any('scientific' in n or ('software' in n and 'application' not in n) for n in subcat_names)
result['subcat_hpc_api'] = hpc_found_api
result['subcat_storage_api'] = storage_found_api
result['subcat_software_api'] = software_found_api

# API checks for departments
depts_resp = api_get('/api/v3/departments', {'list_info': {'row_count': 100}})
departments = (depts_resp.get('departments', []) or
               depts_resp.get('organizations', []) or [])
research_dept_found_api = any('research computing' in (d.get('name', '') or '').lower() for d in departments)
result['dept_research_computing_api'] = research_dept_found_api

# API checks for groups
for endpoint in ['/api/v3/groups', '/api/v3/technician_groups']:
    groups_resp = api_get(endpoint, {'list_info': {'row_count': 100}})
    groups = groups_resp.get('groups', []) or groups_resp.get('technician_groups', [])
    if groups:
        research_group_found_api = any(
            'research computing' in (g.get('name', '') or g.get('group_name', '') or '').lower()
            for g in groups
        )
        result['group_research_computing_api'] = research_group_found_api
        break

# API checks for templates
for endpoint in ['/api/v3/request_templates', '/api/v3/templates']:
    tmpls_resp = api_get(endpoint, {'list_info': {'row_count': 100}})
    templates = (tmpls_resp.get('request_templates', []) or
                 tmpls_resp.get('templates', []) or [])
    if templates:
        hpc_tmpl_found_api = any(
            'hpc' in (t.get('name', '') or '').lower() or
            'cluster access' in (t.get('name', '') or '').lower()
            for t in templates
        )
        result['template_hpc_api'] = hpc_tmpl_found_api
        break

# Consolidate findings
result['dept_created'] = (
    result.get('dept_research_computing_sql', 0) > 0 or
    result.get('dept_research_computing_alt_sql', 0) > 0 or
    result.get('dept_research_computing_api', False)
)
result['category_created'] = (
    result.get('cat_research_computing_sql', 0) > 0 or
    result.get('cat_research_computing_alt_sql', 0) > 0 or
    result.get('cat_research_computing_api', False)
)
result['subcat_hpc_created'] = (
    result.get('subcat_hpc_sql', 0) > 0 or result.get('subcat_hpc_api', False)
)
result['subcat_storage_created'] = (
    result.get('subcat_storage_sql', 0) > 0 or result.get('subcat_storage_api', False)
)
result['subcat_software_created'] = (
    result.get('subcat_software_sql', 0) > 0 or result.get('subcat_software_api', False)
)
result['group_created'] = (
    result.get('group_research_sql', 0) > 0 or
    result.get('group_research_computing_api', False)
)
result['template_created'] = (
    result.get('template_hpc_sql', 0) > 0 or
    result.get('template_hpc_alt_sql', 0) > 0 or
    result.get('template_hpc_api', False)
)

# Count subcategories created
subcats_created = sum([
    result.get('subcat_hpc_created', False),
    result.get('subcat_storage_created', False),
    result.get('subcat_software_created', False)
])
result['subcategories_created_count'] = subcats_created

with open('/tmp/service_catalog_department_setup_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Export complete')
print(json.dumps(result, indent=2))
PYEOF

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo "WARNING: Python export script exited with code $EXIT_CODE"
fi

echo "=== Export Complete ==="
cat "$RESULT_FILE" 2>/dev/null || echo "Result file not found"
