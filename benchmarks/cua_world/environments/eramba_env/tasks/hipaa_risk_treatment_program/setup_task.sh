#!/bin/bash
echo "=== Setting up hipaa_risk_treatment_program task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record baseline counts so the verifier can identify newly created records
BASELINE_RISKS_WITH_TREATMENT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risks WHERE risk_mitigation_strategy_id IS NOT NULL AND deleted=0;" 2>/dev/null || echo "0")
BASELINE_RISKS_TOTAL=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risks WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_SERVICES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_services WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_POLICIES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_policies WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_EXCEPTIONS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM policy_exceptions;" 2>/dev/null || echo "0")
BASELINE_PROJECTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM projects WHERE deleted=0;" 2>/dev/null || echo "0")

# Strip whitespace from counts
BASELINE_RISKS_WITH_TREATMENT=$(echo "$BASELINE_RISKS_WITH_TREATMENT" | tr -d '[:space:]')
BASELINE_RISKS_TOTAL=$(echo "$BASELINE_RISKS_TOTAL" | tr -d '[:space:]')
BASELINE_SERVICES=$(echo "$BASELINE_SERVICES" | tr -d '[:space:]')
BASELINE_POLICIES=$(echo "$BASELINE_POLICIES" | tr -d '[:space:]')
BASELINE_EXCEPTIONS=$(echo "$BASELINE_EXCEPTIONS" | tr -d '[:space:]')
BASELINE_PROJECTS=$(echo "$BASELINE_PROJECTS" | tr -d '[:space:]')

cat > /tmp/hipaa_risk_treatment_program_baseline.txt << EOF
BASELINE_RISKS_WITH_TREATMENT=${BASELINE_RISKS_WITH_TREATMENT}
BASELINE_RISKS_TOTAL=${BASELINE_RISKS_TOTAL}
BASELINE_SERVICES=${BASELINE_SERVICES}
BASELINE_POLICIES=${BASELINE_POLICIES}
BASELINE_EXCEPTIONS=${BASELINE_EXCEPTIONS}
BASELINE_PROJECTS=${BASELINE_PROJECTS}
EOF

echo "Baseline recorded: risks_with_treatment=${BASELINE_RISKS_WITH_TREATMENT}, risks_total=${BASELINE_RISKS_TOTAL}, services=${BASELINE_SERVICES}, policies=${BASELINE_POLICIES}, exceptions=${BASELINE_EXCEPTIONS}, projects=${BASELINE_PROJECTS}"

# Ensure Firefox is running and navigate to Eramba home
ensure_firefox_eramba "http://localhost:8080"
sleep 2
navigate_firefox_to "http://localhost:8080"
sleep 3

take_screenshot /tmp/hipaa_risk_treatment_program_initial.png

echo "=== hipaa_risk_treatment_program task setup complete ==="
echo "Goal: Build HIPAA risk treatment program — create risks, controls, policy, project, and exceptions"
