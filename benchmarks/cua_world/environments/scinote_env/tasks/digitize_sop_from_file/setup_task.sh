#!/bin/bash
echo "=== Setting up digitize_sop_from_file task ==="

# Clean up any previous task files
rm -f /tmp/digitize_sop_result.json 2>/dev/null || true
rm -f /tmp/initial_protocol_count.txt 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create the SOP text file
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/RIPA_Lysis_SOP.txt << 'EOF'
1. Wash cells twice with cold PBS.
2. Add RIPA buffer (1 mL per 10cm dish).
3. Scrape cells and transfer to microcentrifuge tube.
4. Incubate on ice for 30 min.
5. Centrifuge at 14,000xg for 15 min at 4°C.
6. Transfer supernatant to new tube.
EOF

chown ga:ga /home/ga/Documents/RIPA_Lysis_SOP.txt
chmod 644 /home/ga/Documents/RIPA_Lysis_SOP.txt

# Record initial protocol count
INITIAL_COUNT=$(get_protocol_count)
echo "${INITIAL_COUNT:-0}" > /tmp/initial_protocol_count.txt
echo "Initial protocol count: ${INITIAL_COUNT:-0}"

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

# Let UI stabilize
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Create 'RIPA Lysis Protocol' using steps from ~/Documents/RIPA_Lysis_SOP.txt"