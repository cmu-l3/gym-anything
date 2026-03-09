#!/bin/bash
# Setup for "create_request_template" task
# Ensures SDP is running, pre-creates necessary category, and opens Firefox.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Request Template task ==="

# 1. Start SDP and wait for it to be ready
ensure_sdp_running

# 2. Ensure "Network" category exists (so agent can select it)
# We use a safe INSERT that ignores if it already exists
echo "Ensuring 'Network' category exists..."
sdp_db_exec "INSERT INTO categorydefinition (categoryid, categoryname, isdeleted) VALUES ((SELECT COALESCE(MAX(categoryid),0)+1 FROM categorydefinition), 'Network', false) ON CONFLICT DO NOTHING;" 2>/dev/null || \
sdp_db_exec "INSERT INTO categorydefinition (categoryid, categoryname, isdeleted) SELECT COALESCE(MAX(categoryid),0)+1, 'Network', false FROM categorydefinition WHERE NOT EXISTS (SELECT 1 FROM categorydefinition WHERE categoryname='Network');" 2>/dev/null || true

# 3. Record initial state for anti-gaming (count existing templates)
INITIAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM requesttemplate WHERE isdeleted=false;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_template_count.txt
echo "Initial template count: $INITIAL_COUNT"

# 4. Record start timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch Firefox to the Admin or Home page
# We start at Home to force agent to find the Admin/Templates section
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/HomePage.do"

# 6. Capture initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="