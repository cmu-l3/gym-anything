#!/bin/bash
# Export result for "problem_to_fix_full_lifecycle" task
# Collects verification data across Problems, Changes, Requests, and Solutions modules

echo "=== Exporting Problem-to-Fix Full Lifecycle Result ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

RESULT_FILE="/tmp/problem_to_fix_full_lifecycle_result.json"

take_screenshot "/tmp/problem_to_fix_full_lifecycle_final.png" 2>/dev/null || true

# ========================================================================
# SECTION 1: SQL queries for Problems
# ========================================================================

# Find the target problem by title keywords (try both table names — SDP version dependent)
PROBLEM_ID_MAIN=$(sdp_db_exec "SELECT problemid FROM problem WHERE LOWER(title) LIKE '%faulty%' AND (LOWER(title) LIKE '%network switch%' OR LOWER(title) LIKE '%idf-a2%') LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
PROBLEM_ID_ALT=$(sdp_db_exec "SELECT problemid FROM problemdetails WHERE LOWER(title) LIKE '%faulty%' AND (LOWER(title) LIKE '%network switch%' OR LOWER(title) LIKE '%idf-a2%') LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# Broader fallback: match on 'building a' and 'connectivity'
PROBLEM_ID_ALT2=$(sdp_db_exec "SELECT problemid FROM problem WHERE LOWER(title) LIKE '%building a%' AND LOWER(title) LIKE '%connectivity%' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

PROBLEM_ID="${PROBLEM_ID_MAIN:-${PROBLEM_ID_ALT:-${PROBLEM_ID_ALT2:-}}}"

# Problem status
PROBLEM_STATUS=""
if [ -n "$PROBLEM_ID" ]; then
    PROBLEM_STATUS=$(sdp_db_exec "SELECT statusid FROM problem WHERE problemid='${PROBLEM_ID}';" 2>/dev/null | tr -d '[:space:]')
    [ -z "$PROBLEM_STATUS" ] && PROBLEM_STATUS=$(sdp_db_exec "SELECT statusid FROM problemdetails WHERE problemid='${PROBLEM_ID}';" 2>/dev/null | tr -d '[:space:]')
fi

# RCA fields — SDP stores root_cause/symptoms on the problem record (API-accessible),
# and workaround/resolution in the problemresolution table.
# There is no separate 'problemanalysis' table in this SDP version.
RCA_TEXT=""
WORKAROUND_TEXT=""
if [ -n "$PROBLEM_ID" ]; then
    RCA_TEXT=$(sdp_db_exec "SELECT resolution FROM problemresolution WHERE problemid='${PROBLEM_ID}' LIMIT 1;" 2>/dev/null)
    WORKAROUND_TEXT=$(sdp_db_exec "SELECT workaround FROM problemresolution WHERE problemid='${PROBLEM_ID}' LIMIT 1;" 2>/dev/null)
fi

# ========================================================================
# SECTION 2: SQL queries for Changes
# ========================================================================

CHANGE_ID_MAIN=$(sdp_db_exec "SELECT changeid FROM changedetails WHERE LOWER(title) LIKE '%firmware%' AND (LOWER(title) LIKE '%catalyst%' OR LOWER(title) LIKE '%idf-a2%') LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
CHANGE_ID_ALT=$(sdp_db_exec "SELECT changeid FROM changemanagement WHERE LOWER(title) LIKE '%firmware%' AND (LOWER(title) LIKE '%catalyst%' OR LOWER(title) LIKE '%idf-a2%') LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

# Broader fallback
CHANGE_ID_ALT2=$(sdp_db_exec "SELECT changeid FROM changedetails WHERE LOWER(title) LIKE '%emergency%' AND LOWER(title) LIKE '%firmware%' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

CHANGE_ID="${CHANGE_ID_MAIN:-${CHANGE_ID_ALT:-${CHANGE_ID_ALT2:-}}}"

# ========================================================================
# SECTION 3: SQL queries for KB articles
# ========================================================================

KB_FOUND_MAIN=$(sdp_db_exec "SELECT COUNT(*) FROM solution WHERE LOWER(title) LIKE '%cscvz12345%' OR (LOWER(title) LIKE '%catalyst%' AND LOWER(title) LIKE '%port%fail%');" 2>/dev/null | tr -d '[:space:]')
KB_FOUND_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM knowledgebase WHERE LOWER(subject) LIKE '%cscvz12345%' OR (LOWER(subject) LIKE '%catalyst%' AND LOWER(subject) LIKE '%firmware%');" 2>/dev/null | tr -d '[:space:]')

# Write SQL raw data
cat > /tmp/problem_to_fix_lifecycle_sql_raw.json << SQLEOF
{
  "problem_id_sql": "${PROBLEM_ID:-}",
  "problem_status_sql": ${PROBLEM_STATUS:-0},
  "rca_text_sql": $(python3 -c "import json; print(json.dumps('''${RCA_TEXT:-}'''[:500]))" 2>/dev/null || echo '""'),
  "workaround_text_sql": $(python3 -c "import json; print(json.dumps('''${WORKAROUND_TEXT:-}'''[:500]))" 2>/dev/null || echo '""'),
  "change_id_sql": "${CHANGE_ID:-}",
  "kb_found_main": ${KB_FOUND_MAIN:-0},
  "kb_found_alt": ${KB_FOUND_ALT:-0}
}
SQLEOF

# ========================================================================
# SECTION 4: Python REST API queries (comprehensive verification)
# ========================================================================

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

# Load SQL results
with open('/tmp/problem_to_fix_lifecycle_sql_raw.json') as f:
    result = json.load(f)

# ---- PROBLEM VERIFICATION ----

# Find target problem via API
problems_resp = api_get('/api/v3/problems', {'list_info': {'row_count': 50}})
problems = problems_resp.get('problems', [])

target_problem = None
for p in problems:
    title = (p.get('title', '') or '').lower()
    if ('faulty' in title and ('network switch' in title or 'idf-a2' in title)):
        target_problem = p
        break
    if ('building a' in title and 'connectivity' in title):
        target_problem = p
        break

result['problem_found_api'] = target_problem is not None
result['problem_title_api'] = target_problem.get('title', '') if target_problem else ''
result['problem_id_api'] = str(target_problem.get('id', '')) if target_problem else ''

if target_problem:
    prob_id = target_problem.get('id', '')

    # Get full problem details
    prob_detail_resp = api_get(f'/api/v3/problems/{prob_id}')
    prob_detail = prob_detail_resp.get('problem', {})

    # Priority
    prio = prob_detail.get('priority') or {}
    result['problem_priority'] = prio.get('name', '') if prio else ''

    # Impact and Urgency
    impact = prob_detail.get('impact') or {}
    urgency = prob_detail.get('urgency') or {}
    result['problem_impact'] = impact.get('name', '') if impact else ''
    result['problem_urgency'] = urgency.get('name', '') if urgency else ''

    # Status
    status = prob_detail.get('status') or {}
    status_name = status.get('name', '') if status else ''
    result['problem_status_name'] = status_name
    result['problem_is_resolved'] = 'resolved' in status_name.lower() or 'closed' in status_name.lower()

    # Resolution text
    resolution = prob_detail.get('resolution') or {}
    res_text = ''
    if isinstance(resolution, dict):
        res_text = (resolution.get('content', '') or
                    resolution.get('resolution_text', '') or
                    resolution.get('description', '') or '')
    elif isinstance(resolution, str):
        res_text = resolution
    result['problem_resolution_text'] = res_text[:500] if res_text else ''

    # RCA fields from API
    result['rca_from_api'] = prob_detail.get('root_cause', '') or ''
    result['symptoms_from_api'] = prob_detail.get('symptoms', '') or ''
    result['impact_details_from_api'] = prob_detail.get('impact_details', '') or ''

    # Workaround / solution from problem solutions endpoint
    sol_resp = api_get(f'/api/v3/problems/{prob_id}/solutions')
    solutions = sol_resp.get('solutions', [])
    result['problem_solutions_count'] = len(solutions)
    if solutions:
        result['problem_solution_text'] = str(solutions[0])[:500]
    else:
        result['problem_solution_text'] = ''

    # Linked requests (incidents linked to problem)
    linked_requests = (prob_detail.get('requests') or
                       prob_detail.get('related_requests') or
                       prob_detail.get('linked_requests') or [])
    linked_ids = [str(lr.get('id', '')) for lr in linked_requests if lr]
    result['problem_linked_request_ids'] = linked_ids
    result['problem_linked_target_count'] = sum(
        1 for tid in ['1001', '1003', '1004'] if tid in linked_ids
    )

    # Fallback: check from request side if no links found via problem
    if result['problem_linked_target_count'] == 0:
        count_from_req_side = 0
        for woid in [1001, 1003, 1004]:
            r = api_get(f'/api/v3/requests/{woid}')
            req_data = r.get('request', {})
            req_problems = req_data.get('problem') or req_data.get('problems') or []
            if isinstance(req_problems, dict):
                req_problems = [req_problems]
            for rp in req_problems:
                if str(rp.get('id', '')) == str(prob_id):
                    count_from_req_side += 1
                    break
        result['problem_linked_target_count_v2'] = count_from_req_side
else:
    result['problem_priority'] = ''
    result['problem_impact'] = ''
    result['problem_urgency'] = ''
    result['problem_status_name'] = ''
    result['problem_is_resolved'] = False
    result['problem_resolution_text'] = ''
    result['rca_from_api'] = ''
    result['symptoms_from_api'] = ''
    result['impact_details_from_api'] = ''
    result['problem_solutions_count'] = 0
    result['problem_solution_text'] = ''
    result['problem_linked_request_ids'] = []
    result['problem_linked_target_count'] = 0

# ---- CHANGE VERIFICATION ----

changes_resp = api_get('/api/v3/changes', {'list_info': {'row_count': 50}})
changes = changes_resp.get('changes', [])

target_change = None
for c in changes:
    title = (c.get('title', '') or '').lower()
    if ('firmware' in title and ('catalyst' in title or 'idf-a2' in title)):
        target_change = c
        break
    if ('emergency' in title and 'firmware' in title):
        target_change = c
        break

result['change_found_api'] = target_change is not None
result['change_title_api'] = target_change.get('title', '') if target_change else ''
result['change_id_api'] = str(target_change.get('id', '')) if target_change else ''

if target_change:
    change_id = target_change.get('id', '')

    # Change type
    change_type = target_change.get('change_type') or {}
    result['change_type_name'] = change_type.get('name', '') if change_type else ''

    # Impact
    ch_impact = target_change.get('impact') or {}
    result['change_impact'] = ch_impact.get('name', '') if ch_impact else ''

    # Backout plan
    backout = target_change.get('backout_plan', '') or ''
    result['change_backout_plan'] = backout[:500] if backout else ''
    result['has_backout_plan'] = len(backout.strip()) > 10

    # Check if change is linked to problem
    # Try from change side: linked problems
    linked_problems_resp = api_get(f'/api/v3/changes/{change_id}/problems',
                                     {'list_info': {'row_count': 20}})
    linked_problems = (linked_problems_resp.get('problems', []) or
                       linked_problems_resp.get('linked_problems', []) or
                       linked_problems_resp.get('related_problems', []))

    result['change_linked_problem_ids'] = [str(lp.get('id', '')) for lp in linked_problems if lp]

    # Check if our problem is in the linked list
    prob_id_str = result.get('problem_id_api', '') or result.get('problem_id_sql', '')
    result['change_linked_to_problem'] = prob_id_str in result['change_linked_problem_ids']

    # Fallback: check via linked_requests on change (some SDP versions use this)
    if not result['change_linked_to_problem']:
        linked_reqs_resp = api_get(f'/api/v3/changes/{change_id}/linked_requests',
                                     {'list_info': {'row_count': 20}})
        linked_reqs = (linked_reqs_resp.get('linked_requests', []) or
                       linked_reqs_resp.get('requests', []))
        result['change_linked_request_ids'] = [str(lr.get('id', '')) for lr in linked_reqs if lr]

    # Also check from problem side
    if not result['change_linked_to_problem'] and prob_id_str:
        prob_changes_resp = api_get(f'/api/v3/problems/{prob_id_str}/changes',
                                      {'list_info': {'row_count': 20}})
        prob_changes = (prob_changes_resp.get('changes', []) or
                        prob_changes_resp.get('linked_changes', []))
        prob_change_ids = [str(pc.get('id', '')) for pc in prob_changes if pc]
        if str(change_id) in prob_change_ids:
            result['change_linked_to_problem'] = True
        result['problem_linked_change_ids'] = prob_change_ids
else:
    result['change_type_name'] = ''
    result['change_impact'] = ''
    result['change_backout_plan'] = ''
    result['has_backout_plan'] = False
    result['change_linked_problem_ids'] = []
    result['change_linked_to_problem'] = False

# ---- KB ARTICLE VERIFICATION ----

kb_found_api = False
kb_title_api = ''
for endpoint in ['/api/v3/solutions', '/api/v3/knowledge_base_articles']:
    kb_resp = api_get(endpoint, {'list_info': {'row_count': 50}})
    articles = kb_resp.get('solutions', []) or kb_resp.get('articles', []) or []
    if articles:
        for a in articles:
            title = (a.get('title', '') or a.get('subject', '') or '').lower()
            if 'cscvz12345' in title or ('catalyst' in title and ('port' in title or 'firmware' in title)):
                kb_found_api = True
                kb_title_api = a.get('title', '') or a.get('subject', '')
                break
        if kb_found_api:
            break

result['kb_found_api'] = kb_found_api
result['kb_title_api'] = kb_title_api

# ---- CONSOLIDATED RESULTS ----

# Problem found (API or SQL)
result['problem_found'] = result.get('problem_found_api', False) or bool(result.get('problem_id_sql', ''))

# Total linked incidents count (best of both methods)
result['incidents_linked_count'] = max(
    result.get('problem_linked_target_count', 0),
    result.get('problem_linked_target_count_v2', 0)
)

# RCA has content (API fields or DB resolution/workaround)
rca_combined = (result.get('rca_from_api', '') or result.get('rca_text_sql', '') or
                result.get('symptoms_from_api', '') or result.get('impact_details_from_api', '') or
                result.get('problem_resolution_text', '')).lower()
result['rca_has_content'] = len(rca_combined.strip()) > 10
result['rca_has_bug_id'] = 'cscvz12345' in rca_combined

symptoms_combined = (result.get('symptoms_from_api', '') or result.get('impact_details_from_api', '') or
                     result.get('workaround_text_sql', '')).lower()
result['symptoms_has_content'] = len(symptoms_combined.strip()) > 10

# Change found (API or SQL)
result['change_found'] = result.get('change_found_api', False) or bool(result.get('change_id_sql', ''))

# KB found (API or SQL)
result['kb_found'] = result.get('kb_found_api', False) or (
    (result.get('kb_found_main', 0) or 0) > 0 or
    (result.get('kb_found_alt', 0) or 0) > 0
)

with open('/tmp/problem_to_fix_full_lifecycle_result.json', 'w') as f:
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
