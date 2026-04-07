#!/bin/bash
echo "=== Setting up vendor_due_diligence_onboarding task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Delete stale outputs from previous runs
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true
rm -f /tmp/vendor_onboarding_baseline.txt 2>/dev/null || true

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Health check — ensure Eramba is running
echo "Checking Eramba status..."
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/users/login 2>/dev/null || echo "000")
    [ "$HTTP_CODE" = "200" ] && break
    sleep 2
done
if [ "$HTTP_CODE" != "200" ]; then
    echo "WARNING: Eramba may not be fully responsive (HTTP $HTTP_CODE)"
fi

# 4. Record baseline counts for all relevant tables
BASELINE_THIRD_PARTIES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM third_parties WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_TP_RISKS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM third_party_risks WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_SERVICES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_services WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_POLICIES=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM security_policies WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_PROJECTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM projects WHERE deleted=0;" 2>/dev/null || echo "0")
BASELINE_EXCEPTIONS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM risk_exceptions WHERE deleted=0;" 2>/dev/null || echo "0")

# Strip whitespace
BASELINE_THIRD_PARTIES=$(echo "$BASELINE_THIRD_PARTIES" | tr -d '[:space:]')
BASELINE_TP_RISKS=$(echo "$BASELINE_TP_RISKS" | tr -d '[:space:]')
BASELINE_SERVICES=$(echo "$BASELINE_SERVICES" | tr -d '[:space:]')
BASELINE_POLICIES=$(echo "$BASELINE_POLICIES" | tr -d '[:space:]')
BASELINE_PROJECTS=$(echo "$BASELINE_PROJECTS" | tr -d '[:space:]')
BASELINE_EXCEPTIONS=$(echo "$BASELINE_EXCEPTIONS" | tr -d '[:space:]')

cat > /tmp/vendor_onboarding_baseline.txt << EOF
BASELINE_THIRD_PARTIES=${BASELINE_THIRD_PARTIES}
BASELINE_TP_RISKS=${BASELINE_TP_RISKS}
BASELINE_SERVICES=${BASELINE_SERVICES}
BASELINE_POLICIES=${BASELINE_POLICIES}
BASELINE_PROJECTS=${BASELINE_PROJECTS}
BASELINE_EXCEPTIONS=${BASELINE_EXCEPTIONS}
EOF

echo "Baselines: TP=${BASELINE_THIRD_PARTIES}, TPR=${BASELINE_TP_RISKS}, SVC=${BASELINE_SERVICES}, POL=${BASELINE_POLICIES}, Pr=${BASELINE_PROJECTS}, Ex=${BASELINE_EXCEPTIONS}"

# 5. Ensure credentials are discoverable on the Desktop
mkdir -p /home/ga/eramba
cat > /home/ga/eramba/credentials.txt << 'CREDS'
Eramba GRC Platform
URL: http://localhost:8080
Username: admin
Password: Admin2024!
CREDS
chown ga:ga /home/ga/eramba/credentials.txt

cp /home/ga/eramba/credentials.txt /home/ga/Desktop/eramba_credentials.txt 2>/dev/null || true
chown ga:ga /home/ga/Desktop/eramba_credentials.txt 2>/dev/null || true

# 6. Launch Firefox at the Eramba login page
ensure_firefox_eramba "http://localhost:8080"
sleep 2
navigate_firefox_to "http://localhost:8080"
sleep 3

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== vendor_due_diligence_onboarding task setup complete ==="
echo "Goal: Onboard NovaCrest Technologies through full TPRM due diligence process"
