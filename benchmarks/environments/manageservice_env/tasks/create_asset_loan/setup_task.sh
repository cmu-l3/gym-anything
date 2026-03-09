#!/bin/bash
# Setup for "create_asset_loan" task

echo "=== Setting up Create Asset Loan task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Prepare Data (Idempotent SQL)
# We need:
# - An asset 'Epson PowerLite Projector' (AV-PROJ-005) in 'In Store' state
# - A requester 'Emily Sato'
# - No existing open loans for this asset

echo "Preparing Database Data..."

# Clean up any existing loans for this asset (to ensure clean slate)
# Note: Schema is approximate based on standard SDP structures. 
# We target the Resource by name/tag to reset its state.

# SQL to create requester if not exists (Simplified for setup)
# We'll rely on the default admin or create a quick user if possible, 
# but for stability, we often assume the 'Guest' or 'Administrator' exists.
# Here we try to insert Emily Sato if missing.
sdp_db_exec "
INSERT INTO aaauser (user_id, first_name, createdtime)
SELECT (SELECT MAX(user_id)+1 FROM aaauser), 'Emily', 0
WHERE NOT EXISTS (SELECT 1 FROM aaauser WHERE first_name='Emily');

INSERT INTO sduser (userid, status, isvipuser) 
SELECT user_id, 'ACTIVE', 'false' 
FROM aaauser WHERE first_name='Emily' AND NOT EXISTS (SELECT 1 FROM sduser WHERE userid=aaauser.user_id);
"

# SQL to ensure Asset exists and is In Store
# We will just ensure there is a resource with this name.
# If creating complex assets via SQL is too brittle, we assume the environment
# has a baseline or we update an existing dummy asset.
# Let's try to update an existing asset to match our needs or insert a simple one.

sdp_db_exec "
-- Ensure product type exists
INSERT INTO producttype (typeid, typename, description)
SELECT 901, 'Projector', 'Projectors'
WHERE NOT EXISTS (SELECT 1 FROM producttype WHERE typename='Projector');

-- Ensure product exists
INSERT INTO product (productid, productname, typeid)
SELECT 9001, 'Epson PowerLite', 901
WHERE NOT EXISTS (SELECT 1 FROM product WHERE productname='Epson PowerLite');

-- Ensure resource (asset) exists
INSERT INTO resources (resourceid, resourcename, serialno, assettag, productid)
SELECT 90001, 'Epson PowerLite Projector', 'SN-998877', 'AV-PROJ-005', 9001
WHERE NOT EXISTS (SELECT 1 FROM resources WHERE assettag='AV-PROJ-005');

-- Reset state to 'In Store' (State ID 1 usually) and remove user association
UPDATE resourceowner SET userid=NULL WHERE resourceid=(SELECT resourceid FROM resources WHERE assettag='AV-PROJ-005');
UPDATE resources SET resourcestateid=1 WHERE assettag='AV-PROJ-005';
"

# 3. Launch Firefox to Asset Module
# This helps the agent start in the right context
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Wait for window
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="