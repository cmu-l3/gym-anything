#!/bin/bash
# Setup for "configure_sla" task
# Ensures SDP is running, records initial state, and opens the browser.

echo "=== Setting up Configure SLA task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure ServiceDesk Plus is running
ensure_sdp_running

# 2. Record Task Start Time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Record Initial SLA Count (Anti-gaming: "Do Nothing" check)
# We use a python script to query the DB safely
cat > /tmp/count_slas.py << 'PYEOF'
import psycopg2
import sys

try:
    conn = psycopg2.connect(host="localhost", port=65432, user="postgres", database="servicedesk")
    cur = conn.cursor()
    # Try different table names as schema versions vary
    tables = ["sladefinition", "slaconfiguration", "sla"]
    count = 0
    for t in tables:
        try:
            cur.execute(f"SELECT count(*) FROM {t}")
            count = cur.fetchone()[0]
            print(count)
            break
        except:
            conn.rollback()
            continue
except Exception as e:
    print("0")
PYEOF

python3 /tmp/count_slas.py > /tmp/initial_sla_count.txt
echo "Initial SLA count: $(cat /tmp/initial_sla_count.txt)"

# 4. Clear mandatory password change (convenience)
clear_mandatory_password_change

# 5. Launch Firefox to the SDP Home Page
# We start at the home page so the agent has to navigate to Admin
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 6. Maximize Firefox (Critical for visibility)
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Configure SLA task setup complete ==="