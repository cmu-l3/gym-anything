#!/bin/bash
echo "=== Setting up pci_dss_gap_remediation task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record baseline counts (pre-seeded: 1 risk with Mitigate strategy, 2 services, 2 policies, 0 exceptions, 0 projects)
BASELINE_MITIGATE_RISKS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risks WHERE risk_mitigation_strategy_id=3 AND deleted=0;" 2>/dev/null || echo "0")
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

# Strip whitespace
BASELINE_MITIGATE_RISKS=$(echo "$BASELINE_MITIGATE_RISKS" | tr -d '[:space:]')
BASELINE_RISKS_TOTAL=$(echo "$BASELINE_RISKS_TOTAL" | tr -d '[:space:]')
BASELINE_SERVICES=$(echo "$BASELINE_SERVICES" | tr -d '[:space:]')
BASELINE_POLICIES=$(echo "$BASELINE_POLICIES" | tr -d '[:space:]')
BASELINE_EXCEPTIONS=$(echo "$BASELINE_EXCEPTIONS" | tr -d '[:space:]')
BASELINE_PROJECTS=$(echo "$BASELINE_PROJECTS" | tr -d '[:space:]')

cat > /tmp/pci_dss_gap_remediation_baseline.txt << EOF
BASELINE_MITIGATE_RISKS=${BASELINE_MITIGATE_RISKS}
BASELINE_RISKS_TOTAL=${BASELINE_RISKS_TOTAL}
BASELINE_SERVICES=${BASELINE_SERVICES}
BASELINE_POLICIES=${BASELINE_POLICIES}
BASELINE_EXCEPTIONS=${BASELINE_EXCEPTIONS}
BASELINE_PROJECTS=${BASELINE_PROJECTS}
EOF

echo "Baseline: mitigate_risks=${BASELINE_MITIGATE_RISKS}, risks_total=${BASELINE_RISKS_TOTAL}, services=${BASELINE_SERVICES}, policies=${BASELINE_POLICIES}, exceptions=${BASELINE_EXCEPTIONS}, projects=${BASELINE_PROJECTS}"

# Ensure Firefox is running
ensure_firefox_eramba "http://localhost:8080"
sleep 2
navigate_firefox_to "http://localhost:8080"
sleep 3

take_screenshot /tmp/pci_dss_gap_remediation_initial.png

echo "=== pci_dss_gap_remediation task setup complete ==="
echo "Goal: Document 6 PCI-DSS QSA findings as risks with Mitigate treatment, create controls, project, exceptions, and policy"
