#!/bin/bash
# Export result for "incident_resolution_knowledge_base" task

echo "=== Exporting Incident Resolution Knowledge Base Result ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

RESULT_FILE="/tmp/incident_resolution_knowledge_base_result.json"

take_screenshot "/tmp/incident_resolution_knowledge_base_final.png" 2>/dev/null || true

# --- SQL: status of target tickets ---
STATUS_1002=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1002;" 2>/dev/null | tr -d '[:space:]')
STATUS_1005=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1005;" 2>/dev/null | tr -d '[:space:]')

# --- SQL: resolution text for ticket 1002 (email) ---
# Try both table names: 'resolution' and 'workordertoresolution'
RESOLUTION_1002=$(sdp_db_exec "SELECT longdescription FROM resolution WHERE workorderid=1002 LIMIT 1;" 2>/dev/null)
RESOLUTION_1002_ALT=$(sdp_db_exec "SELECT longdescription FROM workordertoresolution WHERE workorderid=1002 LIMIT 1;" 2>/dev/null)
RESOLUTION_1002_ALT2=$(sdp_db_exec "SELECT fulldescription FROM workordertoresolution WHERE workorderid=1002 LIMIT 1;" 2>/dev/null)

# Check if resolution contains 'smtp' or 'relay'
SMTP_IN_RESOLUTION_1002=0
for RES in "$RESOLUTION_1002" "$RESOLUTION_1002_ALT" "$RESOLUTION_1002_ALT2"; do
    if echo "${RES:-}" | grep -qi 'smtp\|relay\|mail server'; then
        SMTP_IN_RESOLUTION_1002=1
        break
    fi
done

# Resolution for ticket 1005 (adobe)
RESOLUTION_1005=$(sdp_db_exec "SELECT longdescription FROM resolution WHERE workorderid=1005 LIMIT 1;" 2>/dev/null)
RESOLUTION_1005_ALT=$(sdp_db_exec "SELECT longdescription FROM workordertoresolution WHERE workorderid=1005 LIMIT 1;" 2>/dev/null)
ACROBAT_IN_RESOLUTION_1005=0
for RES in "$RESOLUTION_1005" "$RESOLUTION_1005_ALT"; do
    if echo "${RES:-}" | grep -qi 'acrobat\|adobe\|sccm\|portal'; then
        ACROBAT_IN_RESOLUTION_1005=1
        break
    fi
done

# --- SQL: KB article count ---
KB_COUNT_NOW=$(sdp_db_exec "SELECT COUNT(*) FROM solution;" 2>/dev/null | tr -d '[:space:]')
KB_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM knowledgebase;" 2>/dev/null | tr -d '[:space:]')
KB_SMTP=$(sdp_db_exec "SELECT COUNT(*) FROM solution WHERE LOWER(title) LIKE '%smtp%' OR LOWER(shortdescription) LIKE '%smtp%';" 2>/dev/null | tr -d '[:space:]')
KB_SMTP_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM solution WHERE LOWER(title) LIKE '%email%' AND (LOWER(title) LIKE '%smtp%' OR LOWER(shortdescription) LIKE '%smtp%');" 2>/dev/null | tr -d '[:space:]')
KB_SMTP_ALT2=$(sdp_db_exec "SELECT COUNT(*) FROM knowledgebase WHERE LOWER(subject) LIKE '%smtp%';" 2>/dev/null | tr -d '[:space:]')

cat > /tmp/incident_resolution_sql_raw.json << SQLEOF
{
  "status_1002": ${STATUS_1002:-2},
  "status_1005": ${STATUS_1005:-2},
  "smtp_in_resolution_1002": ${SMTP_IN_RESOLUTION_1002},
  "acrobat_in_resolution_1005": ${ACROBAT_IN_RESOLUTION_1005},
  "kb_count_now": ${KB_COUNT_NOW:-0},
  "kb_count_alt": ${KB_COUNT_ALT:-0},
  "kb_smtp_count": ${KB_SMTP:-0},
  "kb_smtp_count_alt": ${KB_SMTP_ALT:-0},
  "kb_smtp_count_alt2": ${KB_SMTP_ALT2:-0}
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

with open('/tmp/incident_resolution_sql_raw.json') as f:
    result = json.load(f)

# Check ticket statuses via API (more reliable than SQL for status names)
for woid in [1002, 1005]:
    r = api_get(f'/api/v3/requests/{woid}')
    req_data = r.get('request', {})
    status = req_data.get('status') or {}
    status_name = status.get('name', '').lower() if status else ''
    result[f'status_name_{woid}'] = status.get('name', '') if status else ''
    result[f'is_resolved_{woid}'] = 'resolved' in status_name or 'closed' in status_name
    result[f'is_closed_{woid}'] = 'closed' in status_name

    # Check resolution text via API
    resolution = req_data.get('resolution') or {}
    res_text = (resolution.get('resolution_text') or
                resolution.get('description') or
                resolution.get('content') or
                req_data.get('resolution_description') or '')
    result[f'resolution_text_{woid}'] = res_text[:200] if res_text else ''

# Check resolution text contains keywords
if result.get('resolution_text_1002') and not result.get('smtp_in_resolution_1002'):
    r = result.get('resolution_text_1002', '').lower()
    result['smtp_in_resolution_1002'] = int('smtp' in r or 'relay' in r or 'mail server' in r)

if result.get('resolution_text_1005') and not result.get('acrobat_in_resolution_1005'):
    r = result.get('resolution_text_1005', '').lower()
    result['acrobat_in_resolution_1005'] = int('acrobat' in r or 'adobe' in r or 'sccm' in r)

# KB article check via API
for endpoint in ['/api/v3/solutions', '/api/v3/knowledge_base_articles']:
    kb_resp = api_get(endpoint, {'list_info': {'row_count': 50}})
    articles = kb_resp.get('solutions', []) or kb_resp.get('articles', []) or []
    if articles:
        smtp_article_found = any(
            'smtp' in (a.get('title', '') or a.get('subject', '') or '').lower()
            for a in articles
        )
        result['kb_smtp_found_api'] = smtp_article_found
        break

# Consolidate
result['ticket_1002_resolved'] = (
    result.get('is_resolved_1002', False) or
    (result.get('status_1002', 2) not in (0, 2))
)
result['ticket_1005_resolved'] = (
    result.get('is_resolved_1005', False) or
    (result.get('status_1005', 2) not in (0, 2))
)
result['ticket_1002_closed'] = result.get('is_closed_1002', False)
result['kb_smtp_article_exists'] = (
    result.get('kb_smtp_count', 0) > 0 or
    result.get('kb_smtp_count_alt', 0) > 0 or
    result.get('kb_smtp_count_alt2', 0) > 0 or
    result.get('kb_smtp_found_api', False)
)

with open('/tmp/incident_resolution_knowledge_base_result.json', 'w') as f:
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
