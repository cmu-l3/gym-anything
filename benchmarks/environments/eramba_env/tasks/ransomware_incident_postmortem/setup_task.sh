#!/bin/bash
echo "=== Setting up ransomware_incident_postmortem task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record baseline counts
BASELINE_INCIDENTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_incidents;" 2>/dev/null || echo "0")
BASELINE_RISKS_TOTAL=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risks WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_RISKS_WITH_TREATMENT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risks WHERE risk_mitigation_strategy_id IS NOT NULL AND deleted=0;" 2>/dev/null || echo "0")
BASELINE_SERVICES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_services WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_EXCEPTIONS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM policy_exceptions;" 2>/dev/null || echo "0")
BASELINE_PROJECTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM projects WHERE deleted=0;" 2>/dev/null || echo "0")

# Strip whitespace
BASELINE_INCIDENTS=$(echo "$BASELINE_INCIDENTS" | tr -d '[:space:]')
BASELINE_RISKS_TOTAL=$(echo "$BASELINE_RISKS_TOTAL" | tr -d '[:space:]')
BASELINE_RISKS_WITH_TREATMENT=$(echo "$BASELINE_RISKS_WITH_TREATMENT" | tr -d '[:space:]')
BASELINE_SERVICES=$(echo "$BASELINE_SERVICES" | tr -d '[:space:]')
BASELINE_EXCEPTIONS=$(echo "$BASELINE_EXCEPTIONS" | tr -d '[:space:]')
BASELINE_PROJECTS=$(echo "$BASELINE_PROJECTS" | tr -d '[:space:]')

cat > /tmp/ransomware_incident_postmortem_baseline.txt << EOF
BASELINE_INCIDENTS=${BASELINE_INCIDENTS}
BASELINE_RISKS_TOTAL=${BASELINE_RISKS_TOTAL}
BASELINE_RISKS_WITH_TREATMENT=${BASELINE_RISKS_WITH_TREATMENT}
BASELINE_SERVICES=${BASELINE_SERVICES}
BASELINE_EXCEPTIONS=${BASELINE_EXCEPTIONS}
BASELINE_PROJECTS=${BASELINE_PROJECTS}
EOF

echo "Baseline: incidents=${BASELINE_INCIDENTS}, risks_total=${BASELINE_RISKS_TOTAL}, risks_with_treatment=${BASELINE_RISKS_WITH_TREATMENT}, services=${BASELINE_SERVICES}, exceptions=${BASELINE_EXCEPTIONS}, projects=${BASELINE_PROJECTS}"

# Ensure Firefox is running
ensure_firefox_eramba "http://localhost:8080"
sleep 2
navigate_firefox_to "http://localhost:8080"
sleep 3

take_screenshot /tmp/ransomware_incident_postmortem_initial.png

echo "=== ransomware_incident_postmortem task setup complete ==="
echo "Goal: Document ransomware incident, create post-incident risks, remediation controls, exceptions, and recovery project"
