#!/bin/bash
echo "=== Setting up vendor_risk_management_program task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record baseline counts (pre-seeded: 2 third_parties, 3 risks, 2 with treatment, 2 services, 0 exceptions, 0 projects)
BASELINE_THIRD_PARTIES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM third_parties WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_RISKS_WITH_TREATMENT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risks WHERE risk_mitigation_strategy_id IS NOT NULL AND deleted=0;" 2>/dev/null || echo "0")
BASELINE_RISKS_TOTAL=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risks WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_POLICIES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_policies WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_EXCEPTIONS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM policy_exceptions;" 2>/dev/null || echo "0")
BASELINE_PROJECTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM projects WHERE deleted=0;" 2>/dev/null || echo "0")

# Strip whitespace
BASELINE_THIRD_PARTIES=$(echo "$BASELINE_THIRD_PARTIES" | tr -d '[:space:]')
BASELINE_RISKS_WITH_TREATMENT=$(echo "$BASELINE_RISKS_WITH_TREATMENT" | tr -d '[:space:]')
BASELINE_RISKS_TOTAL=$(echo "$BASELINE_RISKS_TOTAL" | tr -d '[:space:]')
BASELINE_POLICIES=$(echo "$BASELINE_POLICIES" | tr -d '[:space:]')
BASELINE_EXCEPTIONS=$(echo "$BASELINE_EXCEPTIONS" | tr -d '[:space:]')
BASELINE_PROJECTS=$(echo "$BASELINE_PROJECTS" | tr -d '[:space:]')

cat > /tmp/vendor_risk_management_program_baseline.txt << EOF
BASELINE_THIRD_PARTIES=${BASELINE_THIRD_PARTIES}
BASELINE_RISKS_WITH_TREATMENT=${BASELINE_RISKS_WITH_TREATMENT}
BASELINE_RISKS_TOTAL=${BASELINE_RISKS_TOTAL}
BASELINE_POLICIES=${BASELINE_POLICIES}
BASELINE_EXCEPTIONS=${BASELINE_EXCEPTIONS}
BASELINE_PROJECTS=${BASELINE_PROJECTS}
EOF

echo "Baseline: third_parties=${BASELINE_THIRD_PARTIES}, risks_with_treatment=${BASELINE_RISKS_WITH_TREATMENT}, risks_total=${BASELINE_RISKS_TOTAL}, policies=${BASELINE_POLICIES}, exceptions=${BASELINE_EXCEPTIONS}, projects=${BASELINE_PROJECTS}"

# Ensure Firefox is running
ensure_firefox_eramba "http://localhost:8080"
sleep 2
navigate_firefox_to "http://localhost:8080"
sleep 3

take_screenshot /tmp/vendor_risk_management_program_initial.png

echo "=== vendor_risk_management_program task setup complete ==="
echo "Goal: Register 4+ new critical vendors, document vendor risks with treatments, create TPRM policy and project"
