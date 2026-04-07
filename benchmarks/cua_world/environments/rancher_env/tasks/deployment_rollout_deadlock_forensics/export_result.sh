#!/bin/bash
# Export script for deployment_rollout_deadlock_forensics task

echo "=== Exporting deployment_rollout_deadlock_forensics result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# ── Ledger Writer Diagnostics ─────────────────────────────────────────────────
LEDGER_STRATEGY=$(docker exec rancher kubectl get deploy ledger-writer -n financial-ops -o jsonpath='{.spec.strategy.type}' 2>/dev/null || echo "unknown")

LEDGER_V2_RUNNING=$(docker exec rancher kubectl get pods -n financial-ops -l app=ledger-writer -o json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    count = sum(1 for p in data.get('items', [])
                if p.get('status', {}).get('phase') == 'Running' and
                   any(e.get('name') == 'VERSION' and e.get('value') == 'v2'
                       for c in p.get('spec', {}).get('containers', [])
                       for e in c.get('env', [])))
    print(count)
except Exception:
    print(0)
" 2>/dev/null || echo "0")

# ── Risk Analyzer Diagnostics ─────────────────────────────────────────────────
RISK_MAX_SURGE=$(docker exec rancher kubectl get deploy risk-analyzer -n financial-ops -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null || echo "unknown")
RISK_STRATEGY=$(docker exec rancher kubectl get deploy risk-analyzer -n financial-ops -o jsonpath='{.spec.strategy.type}' 2>/dev/null || echo "unknown")

RISK_V2_RUNNING=$(docker exec rancher kubectl get pods -n financial-ops -l app=risk-analyzer -o json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    count = sum(1 for p in data.get('items', [])
                if p.get('status', {}).get('phase') == 'Running' and
                   any(e.get('name') == 'VERSION' and e.get('value') == 'v2'
                       for c in p.get('spec', {}).get('containers', [])
                       for e in c.get('env', [])))
    print(count)
except Exception:
    print(0)
" 2>/dev/null || echo "0")

# ── Compliance API Diagnostics ────────────────────────────────────────────────
COMPLIANCE_SA=$(docker exec rancher kubectl get deploy compliance-api -n financial-ops -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null || echo "unknown")

COMPLIANCE_V2_RUNNING=$(docker exec rancher kubectl get pods -n financial-ops -l app=compliance-api -o json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    count = sum(1 for p in data.get('items', [])
                if p.get('status', {}).get('phase') == 'Running' and
                   any(e.get('name') == 'VERSION' and e.get('value') == 'v2'
                       for c in p.get('spec', {}).get('containers', [])
                       for e in c.get('env', [])))
    print(count)
except Exception:
    print(0)
" 2>/dev/null || echo "0")

# ── Write result JSON ─────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "ledger_strategy": "$LEDGER_STRATEGY",
  "ledger_v2_running": $LEDGER_V2_RUNNING,
  "risk_strategy": "$RISK_STRATEGY",
  "risk_max_surge": "$RISK_MAX_SURGE",
  "risk_v2_running": $RISK_V2_RUNNING,
  "compliance_sa": "$COMPLIANCE_SA",
  "compliance_v2_running": $COMPLIANCE_V2_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/deployment_rollout_deadlock_forensics_result.json 2>/dev/null || sudo rm -f /tmp/deployment_rollout_deadlock_forensics_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/deployment_rollout_deadlock_forensics_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/deployment_rollout_deadlock_forensics_result.json
chmod 666 /tmp/deployment_rollout_deadlock_forensics_result.json 2>/dev/null || sudo chmod 666 /tmp/deployment_rollout_deadlock_forensics_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/deployment_rollout_deadlock_forensics_result.json"
cat /tmp/deployment_rollout_deadlock_forensics_result.json
echo "=== Export complete ==="