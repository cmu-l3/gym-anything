#!/bin/bash
set -e
echo "=== Setting up escalate_finding_to_risk task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Eramba is responsive
echo "Waiting for Eramba..."
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null; then
        break
    fi
    sleep 2
done

# 3. Seed the "Compliance Finding"
# In Eramba, findings are often recorded in 'compliance_analysis'.
# We need to ensure there is a compliance package and item to attach it to, or just insert it.
# To be safe, we'll try to insert a minimal valid record.
echo "Seeding Compliance Finding..."
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e "
-- Create a dummy compliance package if none exists
INSERT INTO compliance_packages (name, description, created, modified)
SELECT 'Internal Audit 2024', 'Internal Audit Findings', NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM compliance_packages WHERE name='Internal Audit 2024');

-- Get the package ID
SET @pkg_id = (SELECT id FROM compliance_packages WHERE name='Internal Audit 2024' LIMIT 1);

-- Insert the finding (Analysis Item)
INSERT INTO compliance_analysis (compliance_package_id, name, description, finding, status, created, modified)
SELECT @pkg_id, 'Unpatched Legacy Payment Server', 'Audit identified legacy server running Windows 2008 R2.', 'Server is EOL and cannot be patched.', 'Fail', NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM compliance_analysis WHERE name='Unpatched Legacy Payment Server');
" 2>/dev/null || echo "Warning: Database seeding encountered non-fatal error"

# 4. Verify seeding worked (internal check)
FINDING_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM compliance_analysis WHERE name='Unpatched Legacy Payment Server'" 2>/dev/null || echo "0")
echo "Findings seeded: $FINDING_COUNT"
echo "$FINDING_COUNT" > /tmp/initial_finding_count.txt

# 5. Launch Firefox to the Dashboard
echo "Launching Firefox..."
ensure_firefox_eramba "http://localhost:8080/dashboard/dashboard"

# 6. Capture initial state
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="