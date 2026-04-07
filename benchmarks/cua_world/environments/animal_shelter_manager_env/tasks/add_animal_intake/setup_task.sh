#!/bin/bash
echo "=== Setting up add_animal_intake task ==="
source /workspace/scripts/task_utils.sh

# Ensure ASM3 is running and accessible
wait_for_http "${ASM_BASE_URL}/login" 60

# Record initial animal count for verification
INITIAL_COUNT=$(asm_query "SELECT COUNT(*) FROM animal" 2>/dev/null | tr -d ' ' || echo "0")
echo "Initial animal count: ${INITIAL_COUNT}"
echo "${INITIAL_COUNT}" > /tmp/initial_animal_count.txt

# Make sure there's no animal named 'Biscuit' already (clean state)
asm_query "DELETE FROM animal WHERE AnimalName = 'Biscuit'" 2>/dev/null || true

# Restart Firefox, auto-login, and navigate to the ASM3 dashboard
# The agent should see the animal shelter dashboard, already logged in
restart_firefox_logged_in "${ASM_BASE_URL}/main"
sleep 2

# Take a screenshot to verify start state
take_screenshot /tmp/task_start_add_animal.png
log "Task setup complete. Firefox showing ASM3 main page."

echo "=== add_animal_intake task setup complete ==="
