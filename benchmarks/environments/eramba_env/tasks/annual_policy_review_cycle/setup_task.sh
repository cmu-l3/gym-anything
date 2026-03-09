#!/bin/bash
echo "=== Setting up annual_policy_review_cycle task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record baseline counts
# Pre-seeded: 2 policies (both Approved/status=1), 0 assets, 0 exceptions, 0 projects
BASELINE_POLICIES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_policies WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_APPROVED_POLICIES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_policies WHERE status=1 AND deleted=0;" 2>/dev/null || echo "0")
BASELINE_DRAFT_POLICIES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_policies WHERE status=0 AND deleted=0;" 2>/dev/null || echo "0")
BASELINE_ASSETS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM assets;" 2>/dev/null || echo "0")
BASELINE_EXCEPTIONS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM policy_exceptions;" 2>/dev/null || echo "0")
BASELINE_PROJECTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM projects WHERE deleted=0;" 2>/dev/null || echo "0")

# Strip whitespace
BASELINE_POLICIES=$(echo "$BASELINE_POLICIES" | tr -d '[:space:]')
BASELINE_APPROVED_POLICIES=$(echo "$BASELINE_APPROVED_POLICIES" | tr -d '[:space:]')
BASELINE_DRAFT_POLICIES=$(echo "$BASELINE_DRAFT_POLICIES" | tr -d '[:space:]')
BASELINE_ASSETS=$(echo "$BASELINE_ASSETS" | tr -d '[:space:]')
BASELINE_EXCEPTIONS=$(echo "$BASELINE_EXCEPTIONS" | tr -d '[:space:]')
BASELINE_PROJECTS=$(echo "$BASELINE_PROJECTS" | tr -d '[:space:]')

cat > /tmp/annual_policy_review_cycle_baseline.txt << EOF
BASELINE_POLICIES=${BASELINE_POLICIES}
BASELINE_APPROVED_POLICIES=${BASELINE_APPROVED_POLICIES}
BASELINE_DRAFT_POLICIES=${BASELINE_DRAFT_POLICIES}
BASELINE_ASSETS=${BASELINE_ASSETS}
BASELINE_EXCEPTIONS=${BASELINE_EXCEPTIONS}
BASELINE_PROJECTS=${BASELINE_PROJECTS}
EOF

echo "Baseline: policies=${BASELINE_POLICIES} (approved=${BASELINE_APPROVED_POLICIES}, draft=${BASELINE_DRAFT_POLICIES}), assets=${BASELINE_ASSETS}, exceptions=${BASELINE_EXCEPTIONS}, projects=${BASELINE_PROJECTS}"

# Ensure Firefox is running
ensure_firefox_eramba "http://localhost:8080"
sleep 2
navigate_firefox_to "http://localhost:8080"
sleep 3

take_screenshot /tmp/annual_policy_review_cycle_initial.png

echo "=== annual_policy_review_cycle task setup complete ==="
echo "Goal: Create 5+ policies (2+ Approved, 2+ Draft), 3+ assets, 3+ exceptions, and policy review project"
