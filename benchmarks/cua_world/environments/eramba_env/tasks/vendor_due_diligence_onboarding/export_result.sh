#!/bin/bash
echo "=== Exporting vendor_due_diligence_onboarding results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

take_screenshot /tmp/task_final.png

# ── Query vendor ─────────────────────────────────────────────────
VENDOR_RAW=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -B -e \
    "SELECT id, name, description FROM third_parties \
     WHERE name LIKE '%NovaCrest%' AND deleted=0 \
     ORDER BY id DESC LIMIT 1;" 2>/dev/null || echo "")

# ── Query third-party risks ─────────────────────────────────────
TP_RISKS_RAW=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -B -e \
    "SELECT id, title, risk_mitigation_strategy_id FROM third_party_risks \
     WHERE deleted=0 \
     AND (title LIKE '%Data Sovereignty%' \
       OR title LIKE '%Vendor Lock%' \
       OR title LIKE '%Shared Responsibility%' \
       OR title LIKE '%Fourth-Party%' \
       OR title LIKE '%NovaCrest%') \
     ORDER BY id;" 2>/dev/null || echo "")

# ── Query security services / internal controls ──────────────────
SERVICES_RAW=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -B -e \
    "SELECT id, name, objective FROM security_services \
     WHERE deleted=0 \
     AND (name LIKE '%Sovereignty%' \
       OR name LIKE '%Encryption Key%' \
       OR name LIKE '%Fourth-Party%' \
       OR name LIKE '%NovaCrest%' \
       OR name LIKE '%Concentration%') \
     ORDER BY id;" 2>/dev/null || echo "")

# ── Query security policy ────────────────────────────────────────
POLICY_RAW=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -B -e \
    "SELECT id, \`index\`, status, description FROM security_policies \
     WHERE (\`index\` LIKE '%Third-Party IaaS%' \
       OR \`index\` LIKE '%IaaS Security%' \
       OR \`index\` LIKE '%NovaCrest%') \
     AND deleted=0 ORDER BY id DESC LIMIT 1;" 2>/dev/null || echo "")

# ── Query project ────────────────────────────────────────────────
PROJECT_RAW=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -B -e \
    "SELECT id, title FROM projects \
     WHERE (title LIKE '%NovaCrest%' OR title LIKE '%Vendor Onboarding%') \
     AND deleted=0 ORDER BY id DESC LIMIT 1;" 2>/dev/null || echo "")

# ── Query risk exceptions ────────────────────────────────────────
EXCEPTIONS_RAW=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -B -e \
    "SELECT id, title, expiration FROM risk_exceptions \
     WHERE (title LIKE '%NovaCrest%' OR title LIKE '%Interim Operations%' OR title LIKE '%Encryption Key Migration%') \
     AND deleted=0 ORDER BY id;" 2>/dev/null || echo "")

# ── Load baseline counts ────────────────────────────────────────
BASELINE_FILE="/tmp/vendor_onboarding_baseline.txt"
if [ -f "$BASELINE_FILE" ]; then
    source "$BASELINE_FILE"
else
    BASELINE_THIRD_PARTIES=0
    BASELINE_TP_RISKS=0
    BASELINE_SERVICES=0
    BASELINE_POLICIES=0
    BASELINE_PROJECTS=0
    BASELINE_EXCEPTIONS=0
fi

# ── Get current counts ──────────────────────────────────────────
CUR_THIRD_PARTIES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM third_parties WHERE deleted=0;" 2>/dev/null | tr -d '[:space:]' || echo "0")
CUR_TP_RISKS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM third_party_risks WHERE deleted=0;" 2>/dev/null | tr -d '[:space:]' || echo "0")
CUR_SERVICES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_services WHERE deleted=0;" 2>/dev/null | tr -d '[:space:]' || echo "0")
CUR_POLICIES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_policies WHERE deleted=0;" 2>/dev/null | tr -d '[:space:]' || echo "0")
CUR_PROJECTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM projects WHERE deleted=0;" 2>/dev/null | tr -d '[:space:]' || echo "0")
CUR_EXCEPTIONS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risk_exceptions WHERE deleted=0;" 2>/dev/null | tr -d '[:space:]' || echo "0")

# ── Assemble JSON via Python ─────────────────────────────────────
python3 << PYEOF
import json, sys

# Parse vendor
vendor = None
vendor_raw = """${VENDOR_RAW}"""
if vendor_raw.strip():
    vparts = vendor_raw.strip().split('\t')
    if len(vparts) >= 3:
        vendor = {"id": vparts[0], "name": vparts[1], "description": vparts[2]}

# Parse risks
tp_risks = []
risks_raw = """${TP_RISKS_RAW}"""
for line in risks_raw.strip().split('\n'):
    if not line.strip():
        continue
    rparts = line.split('\t')
    if len(rparts) >= 3:
        tp_risks.append({
            "id": rparts[0].strip(),
            "title": rparts[1].strip(),
            "strategy_id": rparts[2].strip()
        })

# Parse services
services = []
svc_raw = """${SERVICES_RAW}"""
for line in svc_raw.strip().split('\n'):
    if not line.strip():
        continue
    sparts = line.split('\t')
    if len(sparts) >= 3:
        services.append({
            "id": sparts[0].strip(),
            "name": sparts[1].strip(),
            "objective": sparts[2].strip()
        })

# Parse policy
policy = None
pol_raw = """${POLICY_RAW}"""
if pol_raw.strip():
    pparts = pol_raw.strip().split('\t')
    if len(pparts) >= 4:
        policy = {"id": pparts[0], "title": pparts[1], "status": pparts[2], "description": pparts[3]}
    elif len(pparts) >= 2:
        policy = {"id": pparts[0], "title": pparts[1]}

# Parse project
project = None
proj_raw = """${PROJECT_RAW}"""
if proj_raw.strip():
    pparts = proj_raw.strip().split('\t')
    if len(pparts) >= 2:
        project = {"id": pparts[0], "title": pparts[1]}

# Parse exceptions
exceptions = []
exc_raw = """${EXCEPTIONS_RAW}"""
for line in exc_raw.strip().split('\n'):
    if not line.strip():
        continue
    eparts = line.split('\t')
    if len(eparts) >= 3:
        exceptions.append({
            "id": eparts[0].strip(),
            "title": eparts[1].strip(),
            "expiration": eparts[2].strip()
        })

result = {
    "task_start": int("${TASK_START}" or 0),
    "task_end": int("${TASK_END}" or 0),
    "vendor": vendor,
    "tp_risks": tp_risks,
    "services": services,
    "policy": policy,
    "project": project,
    "exceptions": exceptions,
    "counts": {
        "baseline_third_parties": int("${BASELINE_THIRD_PARTIES}" or 0),
        "baseline_tp_risks": int("${BASELINE_TP_RISKS}" or 0),
        "baseline_services": int("${BASELINE_SERVICES}" or 0),
        "baseline_policies": int("${BASELINE_POLICIES}" or 0),
        "baseline_projects": int("${BASELINE_PROJECTS}" or 0),
        "baseline_exceptions": int("${BASELINE_EXCEPTIONS}" or 0),
        "current_third_parties": int("${CUR_THIRD_PARTIES}" or 0),
        "current_tp_risks": int("${CUR_TP_RISKS}" or 0),
        "current_services": int("${CUR_SERVICES}" or 0),
        "current_policies": int("${CUR_POLICIES}" or 0),
        "current_projects": int("${CUR_PROJECTS}" or 0),
        "current_exceptions": int("${CUR_EXCEPTIONS}" or 0)
    },
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("[export] Result written to /tmp/task_result.json")
PYEOF

chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json
